// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.0 <0.9.0;

contract Auction {
    address public owner;
    
    // Registered users
    mapping (address => bool) public registeredUsers;
    address[] public registeredUserList;
    
    // Tender structure with voting
    struct Tender {
        uint id;
        string title;
        string description;
        uint startingBid;
        uint highestBid;
        address highestBidder;
        uint endTime;
        address createdBy;
        bool isActive;
        bool isAssigned;
        uint upvotes;
        uint downvotes;
        mapping(address => bool) hasVoted;
    }
    
    // Bid structure
    struct Bid {
        address bidder;
        uint amount;
        uint timestamp;
    }
    
    // Mapping from tender ID to array of bids
    mapping(uint => Bid[]) public tenderBids;
    // Mapping to track if an address has bid on a specific tender and their current bid
    mapping(uint => mapping(address => uint)) public bidderAmounts;
    
    Tender[] public tenders;
    uint public tenderCount;
    
    // Events
    event TenderCreated(uint indexed id, string title, address createdBy, uint endTime);
    event BidPlaced(uint indexed tenderId, address bidder, uint amount);
    event TenderAssigned(uint indexed tenderId, address winner, uint amount);
    event Voted(uint indexed tenderId, address voter, bool isUpvote, uint upvotes, uint downvotes);
    
    modifier onlyRegistered() {
        require(registeredUsers[msg.sender], "You are not a registered user");
        _;
    }
    
    modifier notTenderCreator(uint _tenderId) {
        require(tenders[_tenderId].createdBy != msg.sender, "Tender creator cannot bid on their own tender");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        // Register the contract owner by default
        registeredUsers[msg.sender] = true;
        registeredUserList.push(msg.sender);
    }
    
    // Register a user (only owner can register)
    function registerUser(address _user) public {
        require(msg.sender == owner, "Only owner can register users");
        require(!registeredUsers[_user], "User already registered");
        
        registeredUsers[_user] = true;
        registeredUserList.push(_user);
    }
    
    // Create a tender (only registered users)
    function createTender(
        string memory _title,
        string memory _description,
        uint _startingBid,
        uint _durationInMinutes
    ) public onlyRegistered {
        require(_startingBid > 0, "Starting bid must be greater than 0");
        require(_durationInMinutes > 0, "Duration must be greater than 0");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        uint endTime = block.timestamp + (_durationInMinutes * 1 minutes);
        
        Tender storage newTender = tenders.push();
        newTender.id = tenderCount;
        newTender.title = _title;
        newTender.description = _description;
        newTender.startingBid = _startingBid;
        newTender.highestBid = _startingBid;
        newTender.highestBidder = address(0);
        newTender.endTime = endTime;
        newTender.createdBy = msg.sender;
        newTender.isActive = true;
        newTender.isAssigned = false;
        newTender.upvotes = 0;
        newTender.downvotes = 0;
        
        emit TenderCreated(tenderCount, _title, msg.sender, endTime);
        tenderCount++;
    }
    
    // Vote on a tender
    function vote(uint _tenderId, bool _isUpvote) public {
        require(_tenderId < tenders.length, "Tender does not exist");
        Tender storage tender = tenders[_tenderId];
        
        require(!tender.hasVoted[msg.sender], "You have already voted on this tender");
        require(tender.isActive, "Tender is not active");
        
        if (_isUpvote) {
            tender.upvotes++;
        } else {
            tender.downvotes++;
        }
        
        tender.hasVoted[msg.sender] = true;
        
        emit Voted(_tenderId, msg.sender, _isUpvote, tender.upvotes, tender.downvotes);
    }
    
    // Get vote counts for a tender
    function getVotes(uint _tenderId) public view returns (uint upvotes, uint downvotes) {
        require(_tenderId < tenders.length, "Tender does not exist");
        Tender storage tender = tenders[_tenderId];
        return (tender.upvotes, tender.downvotes);
    }
    
    // Check if user has voted on a tender
    function hasUserVoted(uint _tenderId, address _user) public view returns (bool) {
        require(_tenderId < tenders.length, "Tender does not exist");
        return tenders[_tenderId].hasVoted[_user];
    }
    
    // Place a bid on a specific tender
    function placeBid(uint _tenderId) public payable notTenderCreator(_tenderId) {
        require(_tenderId < tenders.length, "Tender does not exist");
        Tender storage tender = tenders[_tenderId];
        
        require(tender.isActive, "Tender is not active");
        require(block.timestamp <= tender.endTime, "Bidding time is over");
        require(msg.value > 0, "Bid amount must be greater than 0");
        
        uint currentBid = bidderAmounts[_tenderId][msg.sender];
        uint newBidAmount = currentBid + msg.value;
        
        if (currentBid == 0) {
            require(newBidAmount > tender.highestBid, "Bid must be higher than current highest bid");
            
            tenderBids[_tenderId].push(Bid({
                bidder: msg.sender,
                amount: newBidAmount,
                timestamp: block.timestamp
            }));
        } else {
            require(newBidAmount > currentBid, "New bid must be higher than your previous bid");
            require(newBidAmount > tender.highestBid, "Bid must be higher than current highest bid");
            
            for (uint i = 0; i < tenderBids[_tenderId].length; i++) {
                if (tenderBids[_tenderId][i].bidder == msg.sender) {
                    tenderBids[_tenderId][i].amount = newBidAmount;
                    tenderBids[_tenderId][i].timestamp = block.timestamp;
                    break;
                }
            }
        }
        
        bidderAmounts[_tenderId][msg.sender] = newBidAmount;
        tender.highestBid = newBidAmount;
        tender.highestBidder = msg.sender;
        
        emit BidPlaced(_tenderId, msg.sender, newBidAmount);
    }
    
    // Assign tender to highest bidder after time ends
    function assignTender(uint _tenderId) public {
        require(_tenderId < tenders.length, "Tender does not exist");
        Tender storage tender = tenders[_tenderId];
        
        require(tender.isActive, "Tender already assigned or inactive");
        require(block.timestamp > tender.endTime, "Bidding time not over yet");
        require(tender.highestBidder != address(0), "No bids placed on this tender");
        require(msg.sender == tender.createdBy || msg.sender == owner, "Only creator or owner can assign");
        
        tender.isActive = false;
        tender.isAssigned = true;
        
        emit TenderAssigned(_tenderId, tender.highestBidder, tender.highestBid);
    }
    
    // Get all tenders
    function getAllTenders() public view returns (
        uint[] memory ids,
        string[] memory titles,
        string[] memory descriptions,
        uint[] memory startingBids,
        uint[] memory highestBids,
        address[] memory highestBidders,
        uint[] memory endTimes,
        address[] memory createdBys,
        bool[] memory isActives,
        bool[] memory isAssigneds,
        uint[] memory upvotes,
        uint[] memory downvotes
    ) {
        uint len = tenders.length;
        
        ids = new uint[](len);
        titles = new string[](len);
        descriptions = new string[](len);
        startingBids = new uint[](len);
        highestBids = new uint[](len);
        highestBidders = new address[](len);
        endTimes = new uint[](len);
        createdBys = new address[](len);
        isActives = new bool[](len);
        isAssigneds = new bool[](len);
        upvotes = new uint[](len);
        downvotes = new uint[](len);
        
        for (uint i = 0; i < len; i++) {
            Tender storage t = tenders[i];
            ids[i] = t.id;
            titles[i] = t.title;
            descriptions[i] = t.description;
            startingBids[i] = t.startingBid;
            highestBids[i] = t.highestBid;
            highestBidders[i] = t.highestBidder;
            endTimes[i] = t.endTime;
            createdBys[i] = t.createdBy;
            isActives[i] = t.isActive;
            isAssigneds[i] = t.isAssigned;
            upvotes[i] = t.upvotes;
            downvotes[i] = t.downvotes;
        }
    }
    
    // Get bids for a specific tender
    function getTenderBids(uint _tenderId) public view returns (Bid[] memory) {
        return tenderBids[_tenderId];
    }
    
    // Check if user is registered
    function isUserRegistered(address _user) public view returns(bool) {
        return registeredUsers[_user];
    }
    
    // Get all registered users
    function getRegisteredUsers() public view returns(address[] memory) {
        return registeredUserList;
    }
    
    // Get bidder's current bid on a tender
    function getBidderAmount(uint _tenderId, address _bidder) public view returns(uint) {
        return bidderAmounts[_tenderId][_bidder];
    }
}
    