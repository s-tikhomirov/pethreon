pragma solidity 0.4.19;

/*
An Ethereum version of recurring payments.

Creator:
    1. publishes address (via website, etc)
    2. can withdraw a certain amount once every PERIOD
    
Supporter:
    1. Deposits ether
    2. Pledges to give N wei to Creator once a PERIOD
    3. Can unsubscribe any time (pledges for earlier periods not refunded)
*/

contract Pethreon {

    /***** EVENTS *****/
    event SupporterDeposited(uint period, address supporter, uint amount);
    event PledgeCreated(uint period, address creator, address supporter, uint weiPerPeriod, uint periods);
    event PledgeCancelled(uint period, address creator, address supporter);
    event SupporterWithdrew(uint period, address supporter, uint amount);
    event CreatorWithdrew(uint period, address creator, uint amount);
    
    /***** CONSTANTS *****/
    // Time is processed in steps of 1 PERIOD
    // Period 0 is the Start of epoch -- i.e., contract creation
    uint period;
    uint startOfEpoch;
    
    /***** DATA STRUCTURES *****/
    struct Pledge {
        address creator;
        uint weiPerPeriod;
        uint afterLastPeriod;   // first period s.t. pledge makes no payment
        bool initialized;
    }
        
    mapping (address => uint) supporterBalances;
    mapping (address => uint) creatorBalances;
    
    // supporter => (creator => pledge)
    mapping(address => mapping(address => Pledge)) pledges;
    
    // creator => (periodNumber => payment) 
    mapping (address => mapping(uint => uint)) expectedPayments;
    mapping (address => uint) afterLastWithdrawalPeriod;
    
    
    /***** HELPER FUNCTIONS *****/
    function Pethreon(uint _period) { 
        startOfEpoch = now; 
        period = _period;
    }
    
    function currentPeriod()
    internal
    view
    returns (uint periodNumber) {
        return (now - startOfEpoch) / period;
    }
    /*
    // TODO: get expected payments in batch (can't return uint[]?)
    function getExpectedPayment(uint period) constant returns (uint expectedPayment) {
        return (period < afterLastWithdrawalPeriod[msg.sender]) ? 0 :
            expectedPayments[msg.sender][period];
    }
    */
    /***** DEPOSIT & WITHDRAW *****/
    
    // Get your (yet unpledged) balance as a supporter
    function balanceAsSupporter()
    public
    view
    returns (uint) {
        return supporterBalances[msg.sender];
    }
    
    function balanceAsCreator()
    public
    view
    returns (uint) {
        // sum up all expected payments from all pledges from all previous periods
        uint256 amount = 0;
        for (var period = afterLastWithdrawalPeriod[msg.sender]; period < currentPeriod(); period++) {
            amount += expectedPayments[msg.sender][period];
        }
        return amount;
    }
    
    // deposit ether to be used in future pledges
    function deposit()
    public
    payable
    returns (uint newBalance) {
        supporterBalances[msg.sender] += msg.value;
        SupporterDeposited(currentPeriod(), msg.sender, msg.value);
        return supporterBalances[msg.sender];
    }
    
    // withdraw ether (generic function)
    function withdraw(bool isSupporter, uint amount)
    internal
    returns (uint newBalance) {
        var balances = isSupporter ? supporterBalances : creatorBalances;
        uint oldBalance = balances[msg.sender];
        if (balances[msg.sender] < amount) return oldBalance;
        balances[msg.sender] -= amount;
        if (!msg.sender.send(amount)) {
            balances[msg.sender] += amount;
            return oldBalance;
        }
        return balances[msg.sender];
    }
    
    // Supporter can choose how much to withdraw
    function withdrawAsSupporter(uint amount)
    public {
        withdraw(true, amount);
        SupporterWithdrew(currentPeriod(), msg.sender, amount);
    }
    
    // Creator can only withdraw the full amount available (keeping it simple!)
    function withdrawAsCreator()
    public {
        var amount = balanceAsCreator();
        afterLastWithdrawalPeriod[msg.sender] = currentPeriod();
        withdraw(false, amount);
        CreatorWithdrew(currentPeriod(), msg.sender, amount);
    }
    
    
    /***** PLEDGES *****/
    
    function canPledge(uint _weiPerPeriod, uint _periods)
    internal
    view
    returns (bool enoughFunds) {
        return (supporterBalances[msg.sender] >= _weiPerPeriod * _periods);
    }
    
    function createPledge(address _creator, uint _weiPerPeriod, uint _periods)
    public {
        
        // must have enough funds
        require(canPledge(_weiPerPeriod, _periods));
        
        // can't pledge twice for same creator (for simplicity)
        // to change pledge parameters, cancel it and create a new one
        require(!pledges[msg.sender][_creator].initialized);
        
        // update creator's mapping of future payments
        for (uint period = currentPeriod(); period < _periods; period++) {
            expectedPayments[_creator][period] += _weiPerPeriod;
        }
        
        // store the data structure so that supporter can cancel pledge
        var pledge = Pledge({
            creator: _creator,
            weiPerPeriod: _weiPerPeriod,
            afterLastPeriod: currentPeriod() + _periods,
            initialized: true
            });
            
        pledges[msg.sender][_creator] = pledge;
        supporterBalances[msg.sender] -= _weiPerPeriod * _periods;
        PledgeCreated(currentPeriod(), _creator, msg.sender, _weiPerPeriod, _periods);
    }
    
    function cancelPledge(address _creator) 
    public {
        var pledge = pledges[msg.sender][_creator];
        require(pledge.initialized);
        supporterBalances[msg.sender] += pledge.weiPerPeriod * (pledge.afterLastPeriod - currentPeriod());
        for (uint period = currentPeriod(); period < pledge.afterLastPeriod; period++) {
            expectedPayments[_creator][period] -= pledge.weiPerPeriod;
        }
        delete pledges[msg.sender][_creator];
        PledgeCancelled(currentPeriod(), _creator, msg.sender);
    }
    
    function myPledgeTo(address _creator)
    public
    view
    returns (uint weiPerPeriod, uint afterLastPeriod) {
        var pledge = pledges[msg.sender][_creator];
        return (pledge.weiPerPeriod, pledge.afterLastPeriod);
    }
    
}

