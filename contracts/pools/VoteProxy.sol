// SPDX-License-Identifier: MIT
// QFinance Contracts V2.0.1

pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";
import "../interfaces/IPoolFactory.sol";

/**
 @dev This contract handles the voting mechanism across QPools. QPDTs
 * must be bonded for the voting period duration in order for their vote
 * to count. Chainlink Keeper compatible contracts will be deployed separately
 * to trigger actions as needed.
 */
contract VoteProxy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    // For working through mapping. Cannot exceed 65,535 as it needs to fit into a uint16.
    uint256 private _totalProposals; 

    // QPool Factory
    IPoolFactory private immutable _factory = IPoolFactory(address(0));

    // Check if there is a current proposal in progress
    mapping (address => bool) private _inProgress;
    // Users can lookup their votes
    mapping (uint => mapping (address => Vote)) private _votes;
    // List of new tokens for each proposal
    mapping (uint => mapping (uint => Token)) private _proposalTokens;
    // uint256 is packed variable of uint16 indices
    mapping (address => uint256) private _poolProposals;
    // All proposals. Increment on creation and use _totalProposals to loop.
    mapping (uint => Proposal) private _proposals;
    // All QPDTs bonded
    mapping (address => mapping (address => uint256)) private _bonded;

    struct Proposal {
        uint160 submitter; // Addresses as uint160 to pack tighter
        uint160 pool;
        uint32 yes; // uint32 max is 4.2949 billion. We must ensure to normalize
        uint32 no; // pool tokens 1e18 otherwise there will be overflow.
        uint32 abstain;
        uint32 ends;
        uint16 index;
        uint8 totalTokens;
        uint8 completed;
    }

    struct Token {
        uint160 token;
        uint8 percent;
    }

    struct Vote {
        uint32 amount;
        uint8 position;
    }

    /**
     @dev Get all pool proposals related to a pool. Unpacks mapping and returns uint array.
     */
    function getPoolProposals(address pool) external view returns (uint256[] memory) {
        require(_poolProposals[pool] != 0, "No pool proposals");
        uint256 poolProposals = _poolProposals[pool];
        Proposal storage proposal = _proposals[uint16(poolProposals)];
        uint256[] memory indices = new uint256[](proposal.totalTokens);
        for (uint i; i < proposal.totalTokens; i++) {
            indices[i] = uint16(poolProposals << (16 * i)); // Shift to left and cut off the rest
        }

        return indices;
    }

    /**
     @dev Get latest proposal for a pool.
     */
    function getLatestPoolProposal(address pool) external view returns (uint256) {
        require(_poolProposals[pool] != 0, "No pool proposals");
        return uint16(_poolProposals[pool]);
    }

    /**
     @dev Returns proposal details based on index.
     */
    function getProposal(uint index) external view returns (Proposal memory) {
        require(_proposals[index].submitter != 0, "Proposal not found");
        Proposal storage proposal = _proposals[index];
        return proposal;
    }

    /**
     @dev Check to see if current block is greater than the proposal end block.
     */
    function checkClosed(uint index) external view returns (bool) {
        require(_proposals[index].submitter != 0, "Proposal not found");
        return block.number > _proposals[index].ends ? true : false;
    }

    /**
     @dev Check if a proposal's rebalance is complete.
     */
    function checkComplete(uint index) external view returns (bool) {
        require(_proposals[index].submitter != 0, "Proposal not found");
        return _proposals[index].completed == 1 ? true : false;
    }

    /**
     @dev Submit a new proposal, given the QPool address, and the new portfolio.
     */
    function submitProposal(address pool, address[] calldata tokens, uint[] calldata percent) external {
        require(tokens.length == percent.length, "Input error");
        require(_factory.checkPool(pool) != 0, "Not a QPool");
        require(!_inProgress[pool], "Proposal in progress");

        uint updated = _totalProposals + 1;

        _poolProposals[pool] = uint16(updated) << 0;

        Proposal memory newProposal = Proposal({
            submitter: uint160(msg.sender),
            pool: uint160(pool),
            ends: uint32(block.number + 133350),
            yes: 0,
            no: 0,
            abstain: 0,
            index: uint16(updated),
            totalTokens: uint8(tokens.length),
            completed: 0
        });

        _proposals[updated] = newProposal;

        for (uint i = 1; i <= tokens.length; i++) {
            _proposalTokens[updated][i + 1] = Token({token: uint160(tokens[i]), percent: uint8(percent[i])});
        }

        _totalProposals = updated;

        _inProgress[pool] = true;
    }

    /**
     @dev Submit a vote on a proposal. Must bond QPDTs for the period.
     */
    function submitVote(address pool, uint vote, uint amountToVote) external {
        require(_inProgress[pool], "No current proposal");
        require(vote > 0 && vote < 4, "No option");
        require(amountToVote > 0, "Amount 0");

        uint proposalId = _poolProposals[pool];
        Proposal storage proposal = _proposals[uint16(proposalId)]; // Must be last item in bitmap

        require(_votes[proposalId][msg.sender].position != 0, "Already voted");

        IERC20 token = IERC20(pool);

        require(token.balanceOf(msg.sender) >= amountToVote, "Vote exceeds amount");
        
        token.safeTransferFrom(msg.sender, address(this), amountToVote);
        _bonded[pool][msg.sender] = amountToVote; // Add amount as bonded
        _votes[proposalId][msg.sender] = Vote({amount: uint32(amountToVote.div(1e18)), position: uint8(vote)}); // Set user vote

        if (vote == 1) {
            proposal.yes = proposal.yes += uint32((amountToVote.div(1e18))); // Normalize from 1e18 for efficient storage
        } else if (vote == 2) {
            proposal.no = proposal.no += uint32((amountToVote.div(1e18)));
        } else if (vote == 3) {
            proposal.abstain = proposal.abstain += uint32((amountToVote.div(1e18)));
        }
    }

    /**
     @dev Update your vote on a proposal. Must have voted previously.
     */
    function changeVote(address pool, uint newVote) external {
        require(_inProgress[pool], "No current proposal");
        require(newVote > 0 && newVote < 4, "No option");
        require(_bonded[pool][msg.sender] > 0, "No vote");

        uint userVotes = _bonded[pool][msg.sender]; // Check existing bonds for pool
        uint proposalIndex = uint32(_poolProposals[pool]);
        Proposal storage proposal = _proposals[proposalIndex];

        Vote storage voteInfo = _votes[proposalIndex][msg.sender];

        require(voteInfo.position != newVote, "Vote is same");

        if (voteInfo.position == 1) {
            proposal.yes -= uint32(userVotes.div(1e18));
        } else if (voteInfo.position == 2) {
            proposal.no -= uint32(userVotes.div(1e18));
        } else if (voteInfo.position == 3) {
            proposal.abstain -= uint32(userVotes.div(1e18));
        }

        if (newVote == 1) {
            proposal.yes += uint32(userVotes.div(1e18));
        } else if (newVote == 2) {
            proposal.no += uint32(userVotes.div(1e18));
        } else if (newVote == 3) {
            proposal.abstain += uint32(userVotes.div(1e18));
        }
    }

    /**
     @dev Withdraws bonded funds. Checks to see if a vote is in progress. If so, it checks if
     * the sender voted. If so, delete the vote and unbond. If not, proceed to unbond.
     */
    function withdraw(address pool) external {
        require(_poolProposals[pool] != 0, "No pool proposals");
        require(_bonded[pool][msg.sender] > 0, "Nothing to return");

        uint amount = _bonded[pool][msg.sender];
        bool inProgress = _inProgress[pool];

        IERC20 token = IERC20(pool);

        if (!inProgress) {
            token.safeTransferFrom(address(this), msg.sender, amount);
        } else {
            // Check if user has voted on the current proposal. If yes, remove votes.
            uint proposalIndex = uint32(_poolProposals[pool]);
            Vote storage voteInfo = _votes[proposalIndex][msg.sender];
            if (voteInfo.position > 0) {
                Proposal storage proposal = _proposals[proposalIndex];
                if (voteInfo.position == 1) {
                    proposal.yes -= uint32(amount.div(1e18));
                } else if (voteInfo.position == 2) {
                    proposal.no -= uint32(amount.div(1e18));
                } else if (voteInfo.position == 3) {
                    proposal.abstain -= uint32(amount.div(1e18));
                }
            }

            token.safeTransferFrom(address(this), msg.sender, amount);
        }
    }

}