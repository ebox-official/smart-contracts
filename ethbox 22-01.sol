// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;


contract ethbox {
    
    struct box {
        address payable sender;
        address recipient;
        bytes32 recipient_pass_hash;
        uint value;
        uint32 timestamp;
        bool taken;
    }
    
    mapping(address => uint[]) public sender_map;
    mapping(address => uint[]) public recipient_map;
    box[] public boxes;
    
    
    function create_box(address _recipient, uint _value, bytes32 _pass_hash, uint32 _timestamp) public payable {
        require((sender_map[msg.sender].length < 10) && (msg.value >= _value));
        
        box memory new_box;
        new_box.sender = payable(msg.sender);
        new_box.recipient = _recipient;
        new_box.recipient_pass_hash = _pass_hash;
        new_box.value = _value;
        new_box.timestamp = _timestamp;
        new_box.taken = false;
        boxes.push(new_box);
        
        sender_map[msg.sender].push(boxes.length - 1);
        recipient_map[_recipient].push(boxes.length - 1);
    }
    
    function clear_box(uint _box_index, string memory _pass) public {
        require((_box_index < boxes.length) && ((msg.sender == boxes[_box_index].sender) || (msg.sender == boxes[_box_index].recipient)) && (boxes[_box_index].value != 0) && (!boxes[_box_index].taken));
        
        box memory this_box = boxes[_box_index];
        
        if((msg.sender == this_box.recipient) && (msg.sender != this_box.sender))
            require(this_box.recipient_pass_hash == keccak256(abi.encodePacked(_pass)));
        
        payable(msg.sender).transfer(this_box.value);
        boxes[_box_index].taken = true;
        
        for(uint8 i = 0; i < sender_map[this_box.sender].length; i++) {
            if(sender_map[this_box.sender][i] == _box_index) {
                if(i != (sender_map[this_box.sender].length - 1))
                    sender_map[this_box.sender][i] = sender_map[this_box.sender][sender_map[this_box.sender].length - 1];
                
                sender_map[this_box.sender].pop();
                break;
            }
        }
        
        for(uint8 i = 0; i < recipient_map[this_box.recipient].length; i++) {
            if(recipient_map[this_box.recipient][i] == _box_index) {
                if(i != (recipient_map[this_box.recipient].length - 1))
                    recipient_map[this_box.recipient][i] = recipient_map[this_box.recipient][recipient_map[this_box.recipient].length - 1];
                
                recipient_map[this_box.recipient].pop();
                break;
            }
        }
    }
    
    function get_boxes() public view returns(box[] memory) {
        return boxes;
    }
        
    fallback() external payable {
    }
    
    constructor() {
    }
}