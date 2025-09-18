import "@stdlib/deploy/Deployable";
import "@stdlib/ownable/Ownable";
import "@stdlib/jetton/JettonWallet"; // For Transfer and InternalTransfer messages

// --- Constants & OP Codes ---
const OP_CREATE_PROPOSAL: Int = 1;
const OP_VOTE: Int = 2;

// --- Structs and Messages ---

// Payloads for staking transfers. The `op` code determines the action.
struct CreateProposalPayload { op: Int as uint32; description: String; voting_duration_seconds: Int as uint64; }
struct VotePayload { op: Int as uint32; proposal_id: Int as uint64; support: Bool; }

// A struct to hold all data related to a single proposal.
struct Proposal {
    proposer: Address;
    description: String;
    creation_time: Int as uint64;
    voting_deadline: Int as uint64;
    yes_votes: Int as coins;
    no_votes: Int as coins;
    staked_funds: map<Address, Int>; // Maps a voter's address to their total staked amount for this proposal
    is_executed: Bool;
}

// Message from a user to reclaim their staked tokens after a vote.
message UnlockTokens {
    proposal_id: Int as uint64;
}

contract Governance with Deployable, Ownable {
    // --- Storage ---
    token_master: Address; // The DerMaster contract address.
    proposals: map<Int, Cell>;
    proposal_seqno: Int as uint64;

    // --- Governance Parameters ---
    const MIN_DER_TO_PROPOSE: Int = 25000000000000; // 25,000 DER
    const PASS_THRESHOLD: Int = 55; // 55%

    init(owner: Address, token_master: Address) {
        self.init_Ownable(owner);
        self.token_master = token_master;
        self.proposals = emptyMap();
        self.proposal_seqno = 0;
    }

    // --- Message Handlers ---

    // Users create proposals and vote by sending tokens to this contract.
    // The forward_payload of the token transfer determines the action.
    receive(msg: InternalTransfer) {
        let payload: Slice = msg.forward_payload.asSlice();
        let op: Int = payload.loadUint(32); // Read the operation code

        if (op == OP_CREATE_PROPOSAL) {
            self.handle_proposal_creation(msg, payload);
        } else if (op == OP_VOTE) {
            self.handle_vote(msg, payload);
        } else {
            dump("Unknown operation code");
        }
    }

    receive(msg: UnlockTokens) {
        let proposalCell: Cell = self.proposals.get(msg.proposal_id)!!;
        let p: Proposal = proposalCell.asSlice().load(Proposal);
        let voter: Address = sender();

        require(block_time() >= p.voting_deadline, "Voting period has not ended yet");

        let staked_amount: Int = p.staked_funds.get(voter) ?? 0;
        require(staked_amount > 0, "You have no tokens to unlock for this proposal");

        p.staked_funds.set(voter, 0); // Reset stake to prevent double-unlocking
        self.proposals.set(msg.proposal_id, beginCell().store(p).endCell());

        // Send the tokens back to the user
        let my_wallet: Address = JettonWallet.get_wallet_address(self.token_master, self.address);
        send(SendParameters{ to: my_wallet, value: 0, mode: SendPayGasSeparately,
            body: Transfer{
                query_id: 0, amount: staked_amount, to: voter, response_destination: voter,
                custom_payload: null, forward_ton_amount: 0, forward_payload: emptyCell()
            }.toCell()
        });
    }

    // --- Internal Logic ---

    fun handle_proposal_creation(msg: InternalTransfer, payload: Slice) {
        require(msg.amount >= MIN_DER_TO_PROPOSE, "Not enough tokens staked to create proposal");
        let proposer: Address = msg.from;
        let p_payload: CreateProposalPayload = payload.load(CreateProposalPayload);

        let now: Int = block_time();
        let new_proposal: Proposal = Proposal{
            proposer: proposer, description: p_payload.description, creation_time: now,
            voting_deadline: now + p_payload.voting_duration_seconds,
            yes_votes: 0, no_votes: 0, staked_funds: emptyMap(), is_executed: false
        };
        // The proposer's stake is automatically recorded.
        new_proposal.staked_funds.set(proposer, msg.amount);

        self.proposals.set(self.proposal_seqno, beginCell().store(new_proposal).endCell());
        self.proposal_seqno = self.proposal_seqno + 1;
    }

    fun handle_vote(msg: InternalTransfer, payload: Slice) {
        let v_payload: VotePayload = payload.load(VotePayload);
        let voter: Address = msg.from;

        let proposalCell: Cell = self.proposals.get(v_payload.proposal_id)!!;
        let p: Proposal = proposalCell.asSlice().load(Proposal);

        require(block_time() < p.voting_deadline, "Voting period has ended");

        if (v_payload.support) { p.yes_votes = p.yes_votes + msg.amount; }
        else { p.no_votes = p.no_votes + msg.amount; }

        let current_stake: Int = p.staked_funds.get(voter) ?? 0;
        p.staked_funds.set(voter, current_stake + msg.amount);

        self.proposals.set(v_payload.proposal_id, beginCell().store(p).endCell());
    }

    // --- Getters ---
    get fun get_proposal(id: Int): Proposal? {
        let pCell: Cell? = self.proposals.get(id);
        if (pCell != null) { return pCell!!.asSlice().load(Proposal); } else { return null; }
    }
}
