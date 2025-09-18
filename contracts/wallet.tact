import "@stdlib/jetton/JettonWallet";

// Message to be sent to the TransactionLog contract.
message LogEntry {
    from: Address;
    to: Address;
    amount: Int as coins;
    fee: Int as coins;
}

// --- Wallet Constants ---
const FEE_PERCENT: Int = 1; // 1% fee
const FEE_MAX: Int = 1_000_000_000_000; // 1,000 DER (with 9 decimals)

// --- Jetton Wallet Contract with Dynamic Configuration ---
contract DerWallet with JettonWallet {

    // --- Storage ---
    // Inherited: balance, owner, master, wallet_code
    // Custom storage for dynamic configuration passed by the master contract.
    treasury_address: Address;
    log_address: Address;
    exempt_addresses: map<Address, Bool>;

    // The wallet is initialized by the master contract, which provides the necessary dynamic addresses.
    init(master: Address, owner: Address, treasury: Address, log: Address, exemptions: Cell) {
        self.init_JettonWallet(master, owner);
        self.treasury_address = treasury;
        self.log_address = log;
        self.exempt_addresses = exemptions.asSlice().loadDict(32); // 32-bit key for Address
    }

    override receive(msg: Transfer) {
        require(sender() == self.owner, "Access denied: sender is not the wallet owner.");

        // --- Fee Calculation ---
        let fee: Int = 0;
        // Check if the recipient address is in the exemption list provided during initialization.
        let is_exempt: Bool = self.exempt_addresses.get(msg.to) ?? false;

        if (!is_exempt) {
            fee = (msg.amount * FEE_PERCENT) / 100;
            if (fee > FEE_MAX) {
                fee = FEE_MAX;
            }
        }

        let total_deduction: Int = msg.amount + fee;
        require(self.balance >= total_deduction, "Insufficient balance for transfer and fee.");

        // --- Send Fee ---
        if (fee > 0) {
            self.send_tokens(
                from = self.owner,
                to = self.treasury_address, // Use address from storage
                amount = fee,
                response_destination = self.owner,
                forward_ton_amount = 0,
                forward_payload = emptyCell()
            );
        }

        // --- Send Main Transfer ---
        self.send_tokens(
            from = self.owner,
            to = msg.to,
            amount = msg.amount,
            response_destination = msg.response_destination,
            forward_ton_amount = msg.forward_ton_amount,
            forward_payload = msg.forward_payload
        );

        // --- Log Transaction ---
        send(SendParameters{
            to: self.log_address, // Use address from storage
            value: 0,
            mode: SendPayGasSeparately,
            bounce: false,
            body: LogEntry{
                from = self.owner,
                to = msg.to,
                amount: msg.amount,
                fee: fee
            }.toCell()
        });
    }
}
