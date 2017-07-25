pragma solidity ^0.4.11;

import "../Application.sol";
import "../../misc/Crontab.sol";


contract AccountingApp is Application, Crontab {

    struct AccountingPeriod {
        address baseToken;

        bytes2 ct_hour;
        bytes2 ct_day;
        bytes2 ct_month;
        bytes2 ct_weekday;
        bytes2 ct_year;
        uint startBlock;
        uint startTimestamp;
        uint endTimestamp;
    }

    AccountingPeriod public defaultAccountingPeriodSettings;
    AccountingPeriod[] public accountingPeriods; // Perhaps use a mapping?

    // The concept of sending tokens to or from the org
    struct Transaction {
        address token;
        int amount;
        address baseToken;
        int baseValue;
        address externalAddress;
        string reference;
        uint timestamp;
        uint accountingPeriodId;  // in which accounting period did this occur
    }

    // The state a transaction update can be.
    // New states should be added to the end to maintain the
    // order of the index when interfacing with web3.
    enum TransactionState {
        New, // not needed?
        PendingApproval,
        Failed,
        Succeeded
    }

    // The change in Transaciton state over time
    struct TransactionUpdate {
        uint transactionId; // Parent Transaction
        TransactionState state;
        string reason;
        address actor; // who performed this update
    }

    Transaction[] public transactions;
    TransactionUpdate[] public transactionUpdates;

    // throttledFunctions[string key] = timstamp last run
    mapping (string => uint) throttledFunctions;

    // Reverse relation of a Transaction ID  -> TransactionsUpdatesIds[]
    // transactionUpdatesRelation[tid] = [tuid_0..tuid_N]
    mapping (uint => uint[]) public transactionUpdatesRelation;

    event Debug(string reason);

    function AccountingApp(address _dao) Application(_dao) {
    }

    function startNextAccountingPeriod() {
        if(accountingPeriods.length == 0 || accountingPeriods[getCurrentAccountingPeriodId()].endTimestamp < now){
            AccountingPeriod memory ap = defaultAccountingPeriodSettings;
            ap.startTimestamp = now;
            uint endTimestamp = next("0", "0", ap.ct_hour, ap.ct_day, ap.ct_month, ap.ct_weekday, ap.ct_year, now);
            ap.endTimestamp = endTimestamp;
            // TODO: store endBlock of last accountingPeriod?
            ap.startBlock = block.number;
            accountingPeriods.push(ap);
        }
    }

    function getCurrentAccountingPeriodId() public constant returns (uint){
        // TODO: perhaps we should store the current accountingPeriod ID
        // separately and allow accounting periods to be generated in advance.
        // For now the current period is the most recent one
        return accountingPeriods.length - 1;
    }

    function getCurrentAccountingPeriod() public constant returns (address, bytes2, bytes2, bytes2, bytes2, bytes2){
        AccountingPeriod memory ap = accountingPeriods[getCurrentAccountingPeriodId()];
        return (ap.baseToken, ap.ct_hour, ap.ct_day, ap.ct_month, ap.ct_weekday, ap.ct_year);
    }

    function getAccountingPeriodLength() public constant returns (uint) {
        return transactions.length;
    }

    // This flattens the last TransactionUpdate with the base Transation to show the current state of the transaction.
    // This assumes that there is at least a single transaction update which is fine if newTransaction is used.
    function getTransactionInfo(uint transactionId) constant returns (address, address, int, string) {
        Transaction memory t = transactions[transactionId];
        uint tuid = transactionUpdatesRelation[transactionId].length - 1;
        uint lastTransactionUpdate = transactionUpdatesRelation[transactionId][tuid];
        TransactionUpdate tu = transactionUpdates[lastTransactionUpdate];
        return (t.externalAddress, t.token, t.amount, t.reference);
    }

    function getTransactionState(uint transactionId) constant returns (TransactionState, string) {
        Transaction memory t = transactions[transactionId];
        uint tuid = transactionUpdatesRelation[transactionId].length - 1;
        uint lastTransactionUpdate = transactionUpdatesRelation[transactionId][tuid];
        TransactionUpdate tu = transactionUpdates[lastTransactionUpdate];
        return (tu.state, tu.reason);
    }

    // onlyDAO 

    function setDefaultAccountingPeriodSettings(address baseToken, bytes2 ct_hour, bytes2 ct_day, bytes2 ct_month, bytes2 ct_weekday, bytes2 ct_year) onlyDAO {
        defaultAccountingPeriodSettings.baseToken = baseToken;
        defaultAccountingPeriodSettings.ct_hour = ct_hour;
        defaultAccountingPeriodSettings.ct_day = ct_day;
        defaultAccountingPeriodSettings.ct_month = ct_month;
        defaultAccountingPeriodSettings.ct_weekday = ct_weekday;
        defaultAccountingPeriodSettings.ct_year = ct_year;
    }

    // Create a new transaction and return the id of the new transaction.
    // externalAddress is where the transication is coming or going to.
    function newTransaction(address externalAddress, address token, int256 amount, string reference) onlyDAO {
        uint tid = transactions.push(Transaction({
            token: token,
            amount: amount,
            // TODO: get base token and exchange rate from oracle
            baseToken: 0x10000000000001,
            baseValue: 1,
            externalAddress: externalAddress,
            reference: reference,
            timestamp: now,
            accountingPeriodId: getCurrentAccountingPeriodId()
        })) - 1;
        // All transactions must have at least one state.
        // To optimize, incoming transactions could go directly to "Suceeded" or "Failed".
        updateTransaction(tid, TransactionState.New, "new");
    }

    // Create new transactionUpdate for the given transaction id
    function updateTransaction(uint transactionId, TransactionState state, string reason) onlyDAO returns (uint) {
        uint tuid = transactionUpdates.push(TransactionUpdate({
            transactionId: transactionId,
            state: state,
            reason: reason,
            actor: msg.sender
        })) - 1;
        transactionUpdatesRelation[transactionId].push(tuid);
    }

    function setTransactionSucceeded(uint transactionId, string reason) onlyDAO {
        updateTransaction(transactionId, TransactionState.Succeeded, reason);
    }

    function setTransactionPendingApproval(uint transactionId, string reason) {
        updateTransaction(transactionId, TransactionState.PendingApproval, reason);
    }

    function setTransactionFailed(uint transactionId, string reason) onlyDAO {
        updateTransaction(transactionId, TransactionState.Failed, reason);
    }


}