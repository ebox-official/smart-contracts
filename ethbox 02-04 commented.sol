// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;


//------------------------------------------------------------------------------------------------------------------
//
// ethbox
//
// ethbox is a smart contract based escrow service. Instead of sending funds from A to B,
// users send funds through ethbox.
//
// Funds are put in "boxes". Each box contains all the relevant data for that transaction.
// Boxes can be secured with a passphrase. Users can request ETH or tokens in return
// for their deposit (= OTC trade).
//
// The passphrase gets hashed twice. This is because the smart contract needs to do
// its own hashing so that it cannot be manipulated - But the passphrase shouldn't
// be submitted in clear-text all over the web, so it gets hashed, and the hash of
// that is stored on the smart contract, so it can recognie when it is given the
// correct passphrase.
//
// Depositing funds into contract = createBox(...)
// Retrieving funds from contract = clearBox(...)
//
//------------------------------------------------------------------------------------------------------------------


contract ethbox
{
    // Transaction data
    struct Box {
        address         payable sender;
        address         recipient;
        bytes32         passHashHash;
        ERC20Interface  sendToken;
        uint            sendValue;
        ERC20Interface  requestToken;
        uint            requestValue;
        uint32          timestamp;
        bool            taken;
    }
    
    address owner;
    Box[] boxes;

    // Map box indexes to addresses for easier handling / privacy, so users are shown only their own boxes by the contract
    mapping(address => uint[]) senderMap;
    mapping(address => uint[]) recipientMap;
    

    // Deposit funds into contract
    function createBox(address _recipient, ERC20Interface _sendToken, uint _sendValue, ERC20Interface _requestToken, uint _requestValue, bytes32 _passHashHash, uint32 _timestamp) external payable
    {
        // Max 20 outgoing boxes per address, for now
        require(senderMap[msg.sender].length < 20, "ethbox currently supports a maximum of 20 outgoing transactions per address.");
    
        Box memory newBox;
        newBox.sender       = payable(msg.sender);
        newBox.recipient    = _recipient;
        newBox.passHashHash = _passHashHash;
        newBox.sendToken    = _sendToken;
        newBox.sendValue    = _sendValue;
        newBox.requestToken = _requestToken;
        newBox.requestValue = _requestValue;
        newBox.timestamp    = _timestamp;
        newBox.taken        = false;
        boxes.push(newBox);
        
        // Save box index to mappings for sender & recipient
        senderMap[msg.sender].push(boxes.length - 1);
        recipientMap[_recipient].push(boxes.length - 1);
        
        if(_sendToken == ERC20Interface(address(0)))
            // Sending ETH
            require(msg.value == _sendValue, "Insufficient ETH!");
        else {
            // Sending tokens
            require(_sendToken.balanceOf(msg.sender) >= _sendValue, "Insufficient tokens!");
            require(_sendToken.transferFrom(msg.sender, address(this), _sendValue), "Transferring tokens to ethbox smart contract failed!");
        }
    }
    
    // Retrieve funds from contract, only as recipient (when sending tokens: have to ask for approval beforehand in web browser interface)
    function clearBox(uint _boxIndex, bytes32 _passHash) external payable
    {
        require((_boxIndex < boxes.length) && (!boxes[_boxIndex].taken), "Invalid box index!");
        require(msg.sender != boxes[_boxIndex].sender, "Please use 'cancelBox' to cancel transactions as sender!");

        // Recipient needs to have correct passphrase (hashed) and requested ETH / tokens
        require(
            (msg.sender == boxes[_boxIndex].recipient)
            && (boxes[_boxIndex].passHashHash == keccak256(abi.encodePacked(_passHash)))
        ,
            "Deposited funds can only be retrieved by recipient with correct with correct passphrase."
        );
        
        setBoxTaken(_boxIndex);
        
        // Transfer requested ETH / tokens to sender
        if(boxes[_boxIndex].requestValue != 0) {
            if(boxes[_boxIndex].requestToken == ERC20Interface(address(0))) {
                require(msg.value == boxes[_boxIndex].requestValue, "Incorrect amount of ETH attached to transaction, has to be exactly as much as requested!");
                payable(boxes[_boxIndex].sender).transfer(msg.value);
            } else {
                require(boxes[_boxIndex].requestToken.balanceOf(msg.sender) >= boxes[_boxIndex].requestValue, "Recipient does not have enough tokens to fulfill sender's request!");
                require(boxes[_boxIndex].requestToken.transferFrom(msg.sender, boxes[_boxIndex].sender, boxes[_boxIndex].requestValue), "Transferring requested tokens to sender failed!");
            }
        }

        // Transfer sent ETH / tokens to recipient
        if(boxes[_boxIndex].sendToken == ERC20Interface(address(0)))
            payable(msg.sender).transfer(boxes[_boxIndex].sendValue);
        else
            require(boxes[_boxIndex].sendToken.transfer(msg.sender, boxes[_boxIndex].sendValue), "Transferring tokens to recipient failed!");
    }
    
    // Cancel transaction, only as sender (when sending tokens: have to ask for approval beforehand in web browser interface)
    function cancelBox(uint _boxIndex) external payable
    {
        require((_boxIndex < boxes.length) && (!boxes[_boxIndex].taken), "Invalid box index!");
        require(msg.sender == boxes[_boxIndex].sender, "Transactions can only be cancelled by sender.");
        
        setBoxTaken(_boxIndex);
        
        // Transfer ETH / tokens back to sender
        if(boxes[_boxIndex].sendToken == ERC20Interface(address(0)))
            payable(msg.sender).transfer(boxes[_boxIndex].sendValue);
        else
            require(boxes[_boxIndex].sendToken.transfer(msg.sender, boxes[_boxIndex].sendValue), "Transferring tokens back to sender failed!");
    }
    
    // Mark box as taken and remove from mappings
    function setBoxTaken(uint _boxIndex) internal
    {
        require((_boxIndex < boxes.length) && (!boxes[_boxIndex].taken), "Invalid box index!");
        
        // Remove box from sender address => box index mapping
        for(uint8 i = 0; i < senderMap[boxes[_boxIndex].sender].length; i++) {
            if(senderMap[boxes[_boxIndex].sender][i] == _boxIndex) {
                if(i != (senderMap[boxes[_boxIndex].sender].length - 1))
                    senderMap[boxes[_boxIndex].sender][i] = senderMap[boxes[_boxIndex].sender][senderMap[boxes[_boxIndex].sender].length - 1];
                
                senderMap[boxes[_boxIndex].sender].pop();
                break;
            }
        }
        
        // Remove box from recipient address => box index mapping
        for(uint8 i = 0; i < recipientMap[boxes[_boxIndex].recipient].length; i++) {
            if(recipientMap[boxes[_boxIndex].recipient][i] == _boxIndex) {
                if(i != (recipientMap[boxes[_boxIndex].recipient].length - 1))
                    recipientMap[boxes[_boxIndex].recipient][i] = recipientMap[boxes[_boxIndex].recipient][recipientMap[boxes[_boxIndex].recipient].length - 1];
                
                recipientMap[boxes[_boxIndex].recipient].pop();
                break;
            }
        }
        
        // Mark box as taken, so it can't be taken another time
        boxes[_boxIndex].taken = true;
    }
    
    // Retrieve single box by index - only for sender / recipient & contract owner
    function getBox(uint _boxIndex) external view returns(Box memory)
    {
        require(
            (msg.sender == owner)
            || (msg.sender == boxes[_boxIndex].sender)
            || (msg.sender == boxes[_boxIndex].recipient)
        , 
            "Transaction data is only accessible by sender or recipient."
        );
        
        return boxes[_boxIndex];
    }
    
    // Retrieve sender address => box index mapping for user
    function getBoxesOutgoing() external view returns(uint[] memory)
    {
        return senderMap[msg.sender];
    }
    
    // Retrieve recipient address => box index mapping for user
    function getBoxesIncoming() external view returns(uint[] memory)
    {
        return recipientMap[msg.sender];
    }
    
    // Retrieve complete boxes array, only for contract owner
    function getBoxesAll() external view returns(Box[] memory)
    {
        require(msg.sender == owner, "Non-specific transaction data is not accessible by the general public.");
        return boxes;
    }
    
    // Retrieve number of boxes, only for contract owner
    function getNumBoxes() external view returns(uint)
    {
        require(msg.sender == owner, "Non-specific transaction data is not accessible by the general public.");
        return boxes.length;
    }
    
    // Don't accept incoming ETH
    fallback() external payable
    {
        revert("Please don't send funds directly to the ethbox smart contract.");
    }
    
    constructor()
    {
        owner = msg.sender;
    }
}


interface ERC20Interface
{
    // Standard ERC 20 token interface

    function totalSupply() external view returns (uint);
    function balanceOf(address tokenOwner) external view returns (uint balance);
    function allowance(address tokenOwner, address spender) external view returns (uint remaining);
    function transfer(address to, uint tokens) external returns (bool success);
    function approve(address spender, uint tokens) external returns (bool success);
    function transferFrom(address from, address to, uint tokens) external returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}
