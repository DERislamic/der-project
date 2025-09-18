import "@stdlib/deploy/Deployable";
import "@stdlib/ownable/Ownable";

// Message to add a new log entry.
message LogEntry {
    from: Address;
    to: Address;
    amount: Int as coins;
    fee: Int as coins;
}

// A struct to hold the log data.
struct Log {
    from: Address;
    to: Address;
    amount: Int as coins;
    fee: Int as coins;
}

// This contract maintains a log of all transactions.
// It is ownable, and only the owner (the DerMaster contract) can write to it.
// This provides a secure, albeit centralized, logging mechanism.
contract TransactionLog with Deployable, Ownable {
    log_seqno: Int as uint64;
    logs: map<Int, Cell>;

    init(owner: Address) {
        self.init_Ownable(owner);
        self.log_seqno = 0;
        self.logs = emptyMap();
    }

    // This message adds a new log entry. It can only be called by the owner.
    receive(msg: LogEntry) {
        self.requireOwner();

        let logData: Log = Log{
            from: msg.from,
            to: msg.to,
            amount: msg.amount,
            fee: msg.fee
        };

        self.logs.set(self.log_seqno, beginCell().store(logData).endCell());
        self.log_seqno = self.log_seqno + 1;
    }

    // A getter function to retrieve a log entry by its sequence number.
    get fun get_log(id: Int): Log? {
        let logCell: Cell? = self.logs.get(id);
        if (logCell != null) {
            return logCell!!.asSlice().load(Log);
        } else {
            return null;
        }
    }
}
