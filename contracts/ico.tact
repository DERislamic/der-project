import "@stdlib/deploy/Deployable";
import "@stdlib/ownable/Ownable";
import "@stdlib/jetton/JettonWallet"; // Needed for the Transfer message

// --- ICO Constants ---
const ICO_ALLOCATION: Int = 50_000_000_000_000_000; // 50,000,000 DER with 9 decimals
const MIN_TON_PURCHASE: Int = 100000000; // 0.1 TON to prevent dust

// --- Custom Messages for Owner ---
message ToggleSale { active: Bool; }
message ChangeStage { stage: Int; }
message WithdrawTON { amount: Int as coins; }

contract ICO with Deployable, Ownable {
    // --- Storage ---
    treasury: Address;          // Address where collected TON will be forwarded.
    token_master: Address;      // The address of the DerMaster contract.
    is_active: Bool;
    current_stage: Int as uint8;
    tokens_sold: Int as coins;
    stage_prices: map<Int, Int>;

    init(owner: Address, treasury: Address, token_master: Address) {
        self.init_Ownable(owner);
        self.treasury = treasury;
        self.token_master = token_master;
        self.is_active = false;
        self.current_stage = 1;
        self.tokens_sold = 0;

        self.stage_prices = emptyMap();
        self.stage_prices.set(1, 30000000); // 0.03 TON per DER
        self.stage_prices.set(2, 50000000); // 0.05 TON per DER
        self.stage_prices.set(3, 80000000); // 0.08 TON per DER
    }

    // A user sends TON to this contract by sending a simple message with value.
    receive() {
        require(self.is_active, "ICO is not active");

        let sender: Address = sender();
        let ton_received: Int = context().value;
        require(ton_received >= MIN_TON_PURCHASE, "Purchase amount is too low");

        // --- Calculation ---
        let price_per_token: Int = self.stage_prices.get(self.current_stage)!!;
        // We multiply by 10^9 because DER has 9 decimals.
        let der_to_send: Int = (ton_received * 1000000000) / price_per_token;

        // --- Checks ---
        require(self.tokens_sold + der_to_send <= ICO_ALLOCATION, "Not enough tokens left in ICO");
        self.tokens_sold = self.tokens_sold + der_to_send;

        // --- Actions ---
        // 1. Forward the received TON to the treasury. We leave a small amount for gas.
        send(SendParameters{
            to: self.treasury,
            value: ton_received - MIN_TON_PURCHASE, // Keep some dust for gas
            mode: SendIgnoreErrors
        });

        // 2. Send the DER tokens to the buyer.
        // The ICO contract must have a jetton wallet for the DER token.
        // It sends a `Transfer` message to its own wallet to initiate the transfer.
        let my_wallet: Address = JettonWallet.get_wallet_address(self.token_master, self.address);
        send(SendParameters{
            to: my_wallet,
            value: 0,
            mode: SendPayGasSeparately, // Pay for this from the contract's TON balance
            body: Transfer{
                query_id: 0,
                amount: der_to_send,
                to: sender, // The buyer's address
                response_destination: sender, // Return unspent gas to the buyer
                custom_payload: null,
                forward_ton_amount: 0,
                forward_payload: emptyCell()
            }.toCell()
        });
    }

    // --- Owner-only functions ---
    receive(msg: ToggleSale) { self.requireOwner(); self.is_active = msg.active; }
    receive(msg: ChangeStage) { self.requireOwner(); require(msg.stage >= 1 && msg.stage <= 3, "Invalid stage"); self.current_stage = msg.stage; }
    receive(msg: WithdrawTON) { self.requireOwner(); send(SendParameters{to: self.owner, value: msg.amount, mode: SendPayGasSeparately}); }
}
