import * as fs from 'fs';
import * as path from 'path';
import { Cell, contractAddress, beginCell, StateInit, Dictionary } from 'ton-core';
import { mnemonicToWalletKey } from 'ton-crypto';
import { compile } from '@tact-lang/compiler';

// This script calculates the future addresses of all singleton contracts in the project.
// It aligns with the corrected `init` signatures of the Tact contracts.

async function main() {
    console.log('--- Address Calculation Script (v2) ---');

    // --- Step 1: Generate KeyPairs for Owner and Treasury ---
    const owner_mnemonics = (await mnemonicToWalletKey([])).mnemonics;
    const owner_key = await mnemonicToWalletKey(owner_mnemonics);
    const owner_address = owner_key.address;

    const treasury_mnemonics = (await mnemonicToWalletKey([])).mnemonics;
    const treasury_key = await mnemonicToWalletKey(treasury_mnemonics);
    const treasury_address = treasury_key.address;

    console.log(`\nIMPORTANT: Save these mnemonics securely!`);
    console.log(`Project Owner Mnemonics: ${owner_mnemonics.join(' ')}`);
    console.log(`Project Owner Address: ${owner_address.toString({ bounceable: false, testOnly: false })}`);
    console.log(`ICO Treasury Mnemonics: ${treasury_mnemonics.join(' ')}`);
    console.log(`ICO Treasury Address: ${treasury_address.toString({ bounceable: false, testOnly: false })}`);

    // --- Step 2: Compile all contracts ---
    let compiled_main: Cell;
    let compiled_ico: Cell;
    let compiled_log: Cell;
    let compiled_gov: Cell;

    try {
        console.log('\n--- Compiling Contracts ---');
        const contractsDir = path.join(__dirname, '..', 'contracts');

        const compileAndGetCode = async (filename: string): Promise<Cell> => {
            const filePath = path.join(contractsDir, filename);
            console.log(`Compiling ${filename}...`);
            const result = await compile({ files: [filePath] });
            if (!result.ok) throw new Error(`Compilation failed for ${filename}: ${result.error}`);
            return result.code;
        };

        compiled_main = await compileAndGetCode('main.tact');
        compiled_ico = await compileAndGetCode('ico.tact');
        compiled_log = await compileAndGetCode('log.tact');
        compiled_gov = await compileAndGetCode('governance.tact');
        console.log('All contracts compiled successfully.');
    } catch (e: any) {
        console.error('\nFATAL ERROR: Could not compile contracts.', e.message);
        return;
    }

    // --- Step 3: Calculate Addresses in Dependency Order ---
    console.log('\n--- Calculating Future Addresses ---');

    // DerMaster Address Calculation: init(owner: Address)
    const derMasterData = beginCell().storeAddress(owner_address).endCell();
    const derMasterStateInit: StateInit = { code: compiled_main, data: derMasterData };
    const derMasterAddress = contractAddress(0, derMasterStateInit);
    console.log(`DerMaster Address: ${derMasterAddress.toString({ bounceable: false, testOnly: false })}`);

    // TransactionLog Address Calculation: init(owner: Address)
    const txLogData = beginCell().storeAddress(derMasterAddress).endCell(); // Owner is DerMaster
    const txLogStateInit: StateInit = { code: compiled_log, data: txLogData };
    const txLogAddress = contractAddress(0, txLogStateInit);
    console.log(`TransactionLog Address: ${txLogAddress.toString({ bounceable: false, testOnly: false })}`);

    // ICO Address Calculation: init(owner: Address, treasury: Address, token_master: Address)
    const icoData = beginCell()
        .storeAddress(owner_address)
        .storeAddress(treasury_address)
        .storeAddress(derMasterAddress)
        .endCell();
    const icoStateInit: StateInit = { code: compiled_ico, data: icoData };
    const icoAddress = contractAddress(0, icoStateInit);
    console.log(`ICO Address: ${icoAddress.toString({ bounceable: false, testOnly: false })}`);

    // Governance Address Calculation: init(owner: Address, token_master: Address)
    const governanceData = beginCell()
        .storeAddress(owner_address)
        .storeAddress(derMasterAddress)
        .endCell();
    const governanceStateInit: StateInit = { code: compiled_gov, data: governanceData };
    const governanceAddress = contractAddress(0, governanceStateInit);
    console.log(`Governance Address: ${governanceAddress.toString({ bounceable: false, testOnly: false })}`);

    console.log('\n--- Script Finished ---');
}

main().catch(e => {
    console.error('An unexpected error occurred:', e);
});
