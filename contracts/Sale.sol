pragma solidity 0.4.11;
import "./HumanStandardToken.sol";
import "./Disbursement.sol";
import "./Filter.sol";

contract Sale {

    /*
     * Events
     */

    event PurchasedTokens(address indexed purchaser, uint amount);
    event TransferredPreBuyersReward(address indexed preBuyer, uint amount);
    event TransferredFoundersTokens(address vault, uint amount);

    /*
     * Storage
     */

    address public owner;
    address public wallet;
    HumanStandardToken public token;
    uint public price;
    uint public startBlock;
    uint public freezeBlock;
    bool public emergencyFlag = false;
    address[] public filters;

    /*
     * Modifiers
     */

    modifier saleStarted {
        require(block.number >= startBlock || msg.sender == owner);
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    modifier notFrozen {
        require(block.number < freezeBlock);
        _;
    }

    modifier notInEmergency {
        require(emergencyFlag == false);
        _;
    }

    /*
     * Public functions
     */

    /// @dev Sale(): constructor for Sale contract
    /// @param _owner the address which owns the sale, can access owner-only functions
    /// @param _wallet the sale's beneficiary address 
    /// @param _tokenSupply the total number of AdToken to mint
    /// @param _tokenName AdToken's human-readable name
    /// @param _tokenDecimals the number of display decimals in AdToken balances
    /// @param _tokenSymbol AdToken's human-readable asset symbol
    /// @param _price price of the token in Wei (ADT/Wei pair price)
    /// @param _startBlock the block at which this contract will begin selling its ADT balance
    /// @param _preBuyers addresses of preBuyers to receive initial token balances
    /// @param _preBuyersTokens amounts of tokens to transfer to preBuyers
    /// @param _founders addresses of founders to receive timelocked tokens
    /// @param _foundersTokens amounts of tokens to disburse to founders over time
    /// @param _founderTimelocks vesting periods as UNIX timestamps
    function Sale(address _owner,
                  address _wallet,
                  uint256 _tokenSupply,
                  string _tokenName,
                  uint8 _tokenDecimals,
                  string _tokenSymbol,
                  uint _price,
                  uint _startBlock,
                  uint _freezeBlock,
                  address[] _preBuyers,
                  uint[] _preBuyersTokens,
                  address[] _founders,
                  uint[] _foundersTokens,
                  uint[] _founderTimelocks) {
        owner = _owner;
        wallet = _wallet;
        token = new HumanStandardToken(_tokenSupply, _tokenName, _tokenDecimals, _tokenSymbol);
        price = _price;
        startBlock = _startBlock;
        freezeBlock = _freezeBlock;

        require(token.transfer(this, token.totalSupply()));
        if (token.balanceOf(this) != token.totalSupply()) throw;
        if (token.balanceOf(this) != 10**9) throw;

        distributePreBuyersRewards(_preBuyers, _preBuyersTokens);

        distributeFoundersRewards(_founders, _foundersTokens, _founderTimelocks);
    }

    /// @dev distributeFoundersRewards(): private utility function called by constructor
    /// @param _preBuyers an array of addresses to which awards will be distributed
    /// @param _preBuyersTokens an array of integers specifying preBuyers rewards
    function distributePreBuyersRewards(address[] _preBuyers, uint[] _preBuyersTokens) 
        private
    { 
        for(uint i = 0; i < _preBuyers.length; i++) {
            require(token.transfer(_preBuyers[i], _preBuyersTokens[i]));
            TransferredPreBuyersReward(_preBuyers[i], _preBuyersTokens[i]);
        }

    }

    /// @dev distributeTimelockedRewards(): private utility function called by constructor
    /// @param _founders an array of addresses specifying disbursement beneficiaries
    /// @param _foundersTokens an array of integers specifying disbursement amounts
    /// @param _founderTimelocks an array of UNIX timestamps specifying vesting dates
    function distributeFoundersRewards(
        address[] _founders,
        uint[] _foundersTokens,
        uint[] _founderTimelocks) 
        private
    { 
        // TODO: SAFE MATH

        // Total number of tokens to be disbursed for a given tranch. Used when
        // tokens are transferred to disbursement contracts.
        uint tokensPerTranch = 0;
        // Alias of founderTimelocks.length for legibility
        uint tranches = _founderTimelocks.length;
        // The number of tokens which may be withdrawn per founder for each tranch
        uint[] memory foundersTokensPerTranch = new uint[](_foundersTokens.length);

        // Compute foundersTokensPerTranch and tokensPerTranch
        for(uint i = 0; i < _foundersTokens.length; i++) {
            foundersTokensPerTranch[i] = _foundersTokens[i]/tranches;
            tokensPerTranch = tokensPerTranch + foundersTokensPerTranch[i];
        }

        // Deploy disbursement and filter contract pairs, initialize both and store
        // filter addresses in filters array. Finally, transfer tokensPerTranch to
        // disbursement contracts.
        for(uint j = 0; j < tranches; j++) {
            Filter filter = new Filter(_founders, foundersTokensPerTranch);
            filters.push(filter);
            Disbursement vault = new Disbursement(filter, 1, _founderTimelocks[j]);
            // Give the disbursement contract the address of the token it disburses.
            vault.setup(token);             
            // Give the filter contract the address of the disbursement contract it access controls
            filter.setup(vault);             
            require(token.transfer(vault, tokensPerTranch));
            TransferredFoundersTokens(vault, tokensPerTranch);
        }
    }

    /// @dev purchaseToken(): function that exchanges ETH for ADT (main sale function)
    /// @notice You're about to purchase the equivalent of `msg.value` Wei in ADT tokens
    function purchaseTokens()
        saleStarted
        payable
        notInEmergency
    {
        uint excessAmount = msg.value % price;
        uint purchaseAmount = msg.value - excessAmount;
        uint tokenPurchase = purchaseAmount / price;

        require(tokenPurchase <= token.balanceOf(this));

        if (excessAmount > 0) {
            msg.sender.transfer(excessAmount);
        }

        wallet.transfer(purchaseAmount);

        require(token.transfer(msg.sender, tokenPurchase));

        PurchasedTokens(msg.sender, tokenPurchase);
    }

    /*
     * Owner-only functions
     */

    function changeOwner(address _newOwner)
        onlyOwner
    {
        owner = _newOwner;
    }

    function changePrice(uint _newPrice)
        onlyOwner
        notFrozen
    {
        price = _newPrice;
    }

    function changeStartBlock(uint _newBlock)
        onlyOwner
        notFrozen
    {
        startBlock = _newBlock;
    }

    function emergencyToggle()
        onlyOwner
    {
        emergencyFlag = !emergencyFlag;
    }
}
