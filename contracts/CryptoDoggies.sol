pragma solidity ^0.4.18;

import "./AccessControl.sol";
import "./ERC721.sol";
import "./SafeMath.sol";

contract DetailedERC721 is ERC721 {
    function name() public view returns (string _name);
    function symbol() public view returns (string _symbol);
}


contract CryptoDoggies is AccessControl, DetailedERC721 {
    using SafeMath for uint256;

    //EVENTS
    event TokenCreated(uint256 tokenId, string name, bytes5 dna, uint256 price, address owner);
    event TokenSold(
        uint256 indexed tokenId,
        string name,
        bytes5 dna,
        uint256 sellingPrice,
        uint256 newPrice,
        address indexed oldOwner,
        address indexed newOwner
        );
    //MAPPINGS
    mapping (uint256 => address) private tokenIdToOwner;
    mapping (uint256 => uint256) private tokenIdToPrice;
    mapping (address => uint256) private ownershipTokenCount;
    mapping (uint256 => address) private tokenIdToApproved;
    //DOGGY STRUCT
    struct Doggy {
        string name;
        bytes5 dna;
    }
    //ARRAY OF DOGS
    Doggy[] private doggies;
    //VARIABLES
    uint256 private startingPrice = 0.01 ether;
    bool private erc721Enabled = false;

    modifier onlyERC721() {
        require(erc721Enabled);
        _;
    }

    //function allows us to specify price when creating a token, can give it immediately to account
    function createToken(string _name, address _owner, uint256 _price) public onlyCLevel {
        //require owner address is valid
        require(_owner != address(0));
        //require price we send in is greater than or equal to starting price
        require(_price >= startingPrice);
        //get DNA for dog
        bytes5 _dna = _generateRandomDna();
        //create the token using _createToken function
        _createToken(_name, _dna, _owner, _price);
    }
    //just specify a name to create the token, price is default starting price
    function createToken(string _name) public onlyCLevel {
        bytes5 _dna = _generateRandomDna();
        _createToken(_name, _dna, address(this), startingPrice);
    }

    function _generateRandomDna() private view returns (bytes5) {
        //block number of blockchain
        uint256 lastBlockNumber = block.number - 1;
        //hash the block number
        bytes32 hashVal = bytes32(block.blockhash(lastBlockNumber));
        bytes5 dna = bytes5((hashVal & 0xffffffff) << 216);
        return dna;
    }

    function _createToken(string _name, bytes5 _dna, address _owner, uint256 _price) private {
        //create doggy in memory, set equal to Doggy struct
        Doggy memory _doggy = Doggy({
            name: _name,
            dna: _dna
        });
        //add that doggy to the array
        uint256 newTokenId = doggies.push(_doggy) - 1;
        //map the tokenID to its price
        tokenIdToPrice[newTokenId] = _price;
        //event called
        TokenCreated(newTokenId, _name, _dna, _price, _owner);
        //transfer the ownership of newTokenId to the new owner
        _transfer(address(0), _owner, newTokenId);
    }

    function getToken(uint256 _tokenId) public view returns (
        string _tokenName,
        bytes5 _dna,
        uint256 _price,
        uint256 _nextPrice,
        address _owner
    ) {
        //get tokenName from the doggies array
        _tokenName = doggies[_tokenId].name;
        //get doggy dna from the doggies array
        _dna = doggies[_tokenId].dna;
        //get price from the mapping
        _price = tokenIdToPrice[_tokenId];
        //get next price from nextPriceOf function
        _nextPrice = nextPriceOf(_tokenId);
        //get owner of token from mapping
        _owner = tokenIdToOwner[_tokenId];
    }

    function getAllTokens() public view returns (
        uint256[],
        uint256[],
        address[]
    ) {
        //call totalSuppy() funciton
        uint256 total = totalSupply();
        //create arrays in memory of size total for the prices, nextPrices, and owners
        uint256[] memory prices = new uint256[](total);
        uint256[] memory nextPrices = new uint256[](total);
        address[] memory owners = new address[](total);
        //iterate through arrays from 0 to total-1
        for (uint256 i = 0; i < total; i++) {
            prices[i] = tokenIdToPrice[i];
            nextPrices[i] = nextPriceOf(i);
            owners[i] = tokenIdToOwner[i];
        }

        return (prices, nextPrices, owners);
    }
    //returns a list of tokens that owner owns
    function tokensOf(address _owner) public view returns(uint256[]) {
        //get the balance of the owner
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) { //if zero we can return an empty array
            return new uint256[](0);
        } else {
            //array in memory of size of token count
            uint256[] memory result = new uint256[](tokenCount);
            uint256 total = totalSupply();
            uint256 resultIndex = 0;
            //go through all tokens, check if tokenIdToOwner mapping for each token is owner
            for (uint256 i = 0; i < total; i++) {
                if (tokenIdToOwner[i] == _owner) {
                    result[resultIndex] = i;
                    resultIndex++;
                }
            }
            return result;
        }
    }
    //contract will have value, we can send that value to an address
    function withdrawBalance(address _to, uint256 _amount) public onlyCEO {
        require(_amount <= this.balance);

        if (_amount == 0) {
            _amount = this.balance;
        }

        if (_to == address(0)) {
            ceoAddress.transfer(_amount);
        } else {
            _to.transfer(_amount);
        }
    }

    function purchase(uint256 _tokenId) public payable whenNotPaused {
        //oldOwner is the current owner of the tokenID
        address oldOwner = ownerOf(_tokenId);
        //newOwner is the person initiating transaction, calling function
        address newOwner = msg.sender;
        //selling price is the price of the tokenID
        uint256 sellingPrice = priceOf(_tokenId);
        //require old owner and new owner addresses are valid
        require(oldOwner != address(0));
        require(newOwner != address(0));
        //require old owner is not new owner
        require(oldOwner != newOwner);
        //require new owner is not contract, the contract should not own any tokens
        require(!_isContract(newOwner));
        //selling price checks
        require(sellingPrice > 0);
        require(msg.value >= sellingPrice);
        //call transfer function
        _transfer(oldOwner, newOwner, _tokenId);
        tokenIdToPrice[_tokenId] = nextPriceOf(_tokenId);
        //event
        TokenSold(
            _tokenId,
            doggies[_tokenId].name,
            doggies[_tokenId].dna,
            sellingPrice,
            priceOf(_tokenId),
            oldOwner,
            newOwner
        );
        //if they send too much ether
        uint256 excess = msg.value.sub(sellingPrice);
        uint256 contractCut = sellingPrice.mul(6).div(100); // 6% cut

        if (oldOwner != address(this)) {
            oldOwner.transfer(sellingPrice.sub(contractCut));
        }
        //return extra ether back to newOwner
        if (excess > 0) {
            newOwner.transfer(excess);
        }
    }

    function priceOf(uint256 _tokenId) public view returns (uint256 _price) {
        return tokenIdToPrice[_tokenId];
    }

    uint256 private increaseLimit1 = 0.02 ether;
    uint256 private increaseLimit2 = 0.5 ether;
    uint256 private increaseLimit3 = 2.0 ether;
    uint256 private increaseLimit4 = 5.0 ether;
    //after each purchase, increase price of dog, gives new owner opportunity to profit
    function nextPriceOf(uint256 _tokenId) public view returns (uint256 _nextPrice) {
        uint256 _price = priceOf(_tokenId);
        if (_price < increaseLimit1) {
            return _price.mul(200).div(95);
        } else if (_price < increaseLimit2) {
            return _price.mul(135).div(96);
        } else if (_price < increaseLimit3) {
            return _price.mul(125).div(97);
        } else if (_price < increaseLimit4) {
            return _price.mul(117).div(97);
        } else {
            return _price.mul(115).div(98);
        }
    }

    function enableERC721() public onlyCEO {
        erc721Enabled = true;
    }

    function totalSupply() public view returns (uint256 _totalSupply) {
        _totalSupply = doggies.length;
    }

    function balanceOf(address _owner) public view returns (uint256 _balance) {
        _balance = ownershipTokenCount[_owner];
    }

    function ownerOf(uint256 _tokenId) public view returns (address _owner) {
        _owner = tokenIdToOwner[_tokenId];
    }

    function approve(address _to, uint256 _tokenId) public whenNotPaused onlyERC721 {
        //require that the sender owns the token
        require(_owns(msg.sender, _tokenId));
        tokenIdToApproved[_tokenId] = _to;
        Approval(msg.sender, _to, _tokenId);
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public whenNotPaused onlyERC721 {
        //require to address is valid
        require(_to != address(0));
        //require from account owns the token
        require(_owns(_from, _tokenId));
        //require that approved is correct
        require(_approved(msg.sender, _tokenId));
        //perform transfer
        _transfer(_from, _to, _tokenId);
    }

    function transfer(address _to, uint256 _tokenId) public whenNotPaused onlyERC721 {
        //require to address is valid
        require(_to != address(0));
        //require that sender owns the token
        require(_owns(msg.sender, _tokenId));
        //transfet the token
        _transfer(msg.sender, _to, _tokenId);
    }

    function implementsERC721() public view whenNotPaused returns (bool) {
        return erc721Enabled;
    }

    function takeOwnership(uint256 _tokenId) public whenNotPaused onlyERC721 {
        //requires that the sender is approved
        require(_approved(msg.sender, _tokenId));
        _transfer(tokenIdToOwner[_tokenId], msg.sender, _tokenId);
    }

    function name() public view returns (string _name) {
        _name = "CryptoDoggies";
    }

    function symbol() public view returns (string _symbol) {
        _symbol = "CDT";
    }
    //checks that token of _tokenId is owned by _claimant
    function _owns(address _claimant, uint256 _tokenId) private view returns (bool) {
        return tokenIdToOwner[_tokenId] == _claimant;
    }
    //checks if token is approved for address _to
    function _approved(address _to, uint256 _tokenId) private view returns (bool) {
        return tokenIdToApproved[_tokenId] == _to;
    }
    //transfers ownership of token to another address
    function _transfer(address _from, address _to, uint256 _tokenId) private {
        //increment ownershipTokenCount of _to by 1
        ownershipTokenCount[_to]++;
        tokenIdToOwner[_tokenId] = _to;
        //if _from address is correct
        if (_from != address(0)) {
            //decrement ownershipTokenCount by 1
            ownershipTokenCount[_from]--;
            //delete approval
            delete tokenIdToApproved[_tokenId];
        }
        //emit transfer event
        Transfer(_from, _to, _tokenId);
    }
    //check to see if address is a contract or not
    function _isContract(address addr) private view returns (bool) {
        uint256 size;
        //if size is greater that zero than address is a contract 
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
}
