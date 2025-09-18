import "@stdlib/deploy/Deployable";
import "@stdlib/ownable/Ownable";
import "@stdlib/jetton/JettonWallet"; // For wallet code and messages

// This contract is a custom implementation of a TEP-74 Jetton Master.
// It does not use the JettonMaster trait to allow for full control over
// the initialization of the custom DerWallet contracts.

// --- Constants ---
const NAME: String = "Islamic Economic Republic";
const SYMBOL: String = "DER";
const DESCRIPTION: String = "DEFI HALAL ON TON";
const IMAGE_URL: String = "ipfs://bafybeig34dpy4aerkk7brk5rt7mz64hi3deeh6uvfgnww2k22zhipmcx34";
const DECIMALS: String = "9";
const TOTAL_SUPPLY: Int = 100_250_000_000_000_000;

// --- Custom Messages ---
message Mint { amount: Int as coins; receiver: Address; }
message SetInitialAddresses {
    treasury: Address;
    ico: Address;
    governance: Address;
    log: Address;
}
message UpdateExemptAddress { address: Address; is_exempt: Bool; }

contract DerMaster with Deployable, Ownable {

    // --- Storage ---
    total_supply: Int as coins;
    total_minted: Int as coins;
    content: Cell;
    wallet_code: Cell;

    // Configurable addresses
    treasury_address: Address?;
    ico_address: Address?;
    governance_address: Address?;
    log_address: Address?;
    exempt_addresses: map<Address, Bool>;

    init(owner: Address) {
        self.init_Ownable(owner);
        self.total_supply = TOTAL_SUPPLY;
        self.total_minted = 0;
        self.content = self.create_jetton_content();
        self.wallet_code = init_wallet_code(self.address); // Get wallet code
        self.exempt_addresses = emptyMap();
    }

    // --- Message Handlers ---

    receive(msg: Mint) {
        self.requireOwner();
        require(self.total_minted + msg.amount <= self.total_supply, "Mint amount exceeds total supply");

        // Mint tokens by deploying/funding a jetton wallet for the receiver
        let wallet_init: StateInit = self.get_wallet_init(msg.receiver);
        send(SendParameters{
            to: contractAddress(wallet_init),
            value: 0,
            mode: SendPayGasSeparately,
            bounce: false,
            body: InternalTransfer{
                query_id: 0,
                amount: msg.amount,
                from: self.address,
                response_address: self.owner,
                forward_ton_amount: 0,
                forward_payload: emptyCell()
            }.toCell(),
            code: wallet_init.code,
            data: wallet_init.data
        });

        self.total_minted = self.total_minted + msg.amount;
    }

    receive(msg: SetInitialAddresses) {
        self.requireOwner();
        require(self.ico_address == null, "Addresses have already been set.");

        self.treasury_address = msg.treasury;
        self.ico_address = msg.ico;
        self.governance_address = msg.governance;
        self.log_address = msg.log;

        self.exempt_addresses.set(msg.ico, true);
        self.exempt_addresses.set(msg.governance, true);
        self.exempt_addresses.set(msg.log, true);
        self.exempt_addresses.set(msg.treasury, true);
    }

    receive(msg: UpdateExemptAddress) {
        self.requireOwner();
        self.exempt_addresses.set(msg.address, msg.is_exempt);
    }

    // --- Getters ---

    get fun get_wallet_init(owner: Address): StateInit {
        // This function creates the initial state for a new wallet contract.
        // It injects all the necessary dynamic addresses.
        require(self.treasury_address != null, "Treasury address not set");
        require(self.log_address != null, "Log address not set");

        let data: Cell = beginCell()
            .storeAddress(self.address) // master address
            .storeAddress(owner)
            .storeAddress(self.treasury_address!!)
            .storeAddress(self.log_address!!)
            .storeDict(self.exempt_addresses)
        .endCell();

        return StateInit{
            code: self.wallet_code,
            data: data
        };
    }

    get fun get_wallet_address(owner: Address): Address {
        return contractAddress(self.get_wallet_init(owner));
    }

    get fun get_jetton_data(): JettonData {
        return JettonData{
            total_supply: self.total_supply,
            mintable: self.total_minted < self.total_supply,
            owner: self.owner,
            content: self.content,
            wallet_code: self.wallet_code
        };
    }

    // --- Helper Functions ---
    fun create_jetton_content(): Cell {
        let dict: map<Int, Cell> = emptyMap();
        dict.set(cell_hash(beginCell().storeStringTail("name").endCell()), self.create_string_cell(NAME));
        dict.set(cell_hash(beginCell().storeStringTail("symbol").endCell()), self.create_string_cell(SYMBOL));
        dict.set(cell_hash(beginCell().storeStringTail("description").endCell()), self.create_string_cell(DESCRIPTION));
        dict.set(cell_hash(beginCell().storeStringTail("image").endCell()), self.create_string_cell(IMAGE_URL));
        dict.set(cell_hash(beginCell().storeStringTail("decimals").endCell()), self.create_string_cell(DECIMALS));
        return beginCell().storeUint(0x00, 8).storeDict(dict).endCell();
    }
    fun create_string_cell(s: String): Cell { return beginCell().storeStringTail(s).endCell(); }
}

// Dummy function to get wallet code - in a real project, this is handled by the build system.
native init_wallet_code(master: Address): Cell;
