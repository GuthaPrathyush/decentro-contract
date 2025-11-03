// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

contract Entities {

    enum DocumentStatus {
        Pending,
        VerifierApproved,
        AdminApproved,
        Rejected
    }

    enum UserRoles {
        Stranger,
        User,
        Verifier,
        Admin,
        Recoverer
    }

    struct Document {
        string name;
        string ipfsHash;
        DocumentStatus status;
        address verifiedBy;
        string reason;
        uint256 timestamp;
    }

    struct User {
        string firstName;
        string lastName;
        address walletAddress;
        string email;
        string mobile;
    }
}

library Queue {
    struct QueueItem {
        bytes32 data;
        bytes32 next;
    }

    struct LinkedQueue {
        mapping(bytes32 => bytes32) queueItems;
        bytes32 front;
        bytes32 back;
        uint256 length;
    }

    // Enqueue function for adding items to the queue
    function enqueue(LinkedQueue storage queue, string memory userDoc) internal {
        bytes32 encodedUserDoc = keccak256(abi.encodePacked(userDoc));
        if (queue.back == bytes32(0)) {
            queue.queueItems[encodedUserDoc] = bytes32(0);
            queue.front = encodedUserDoc;
            queue.back = encodedUserDoc;
            queue.length = 1;
        } else {
            queue.queueItems[queue.back] = encodedUserDoc;
            queue.queueItems[encodedUserDoc] = bytes32(0);
            queue.back = encodedUserDoc;
            queue.length++;
        }
    }

    // Dequeue function for removing the front item
    function dequeue(LinkedQueue storage queue, string memory userDoc) internal {
        require(queue.front != bytes32(0), "Queue is empty");
        bytes32 encodedUserDoc = keccak256(abi.encodePacked(userDoc));
        if(queue.front == encodedUserDoc) {
            queue.front = queue.queueItems[queue.front];
        }
        else {
            bytes32 dequeuedData = queue.front;
            while(dequeuedData != bytes32(0) && queue.queueItems[dequeuedData] != encodedUserDoc) {
                dequeuedData = queue.queueItems[dequeuedData];
            }
            require(dequeuedData != bytes32(0), "The requested Document does not exist in the Queue!");
            queue.queueItems[dequeuedData] = queue.queueItems[queue.queueItems[dequeuedData]];
            if(queue.back == encodedUserDoc) {
                queue.back = bytes32(0);
            }
        }
        queue.length--;
        if (queue.front == bytes32(0)) { 
            queue.back = bytes32(0); // Queue is now empty
            queue.length = 0;
        }
    }

    // Peek function to see the front item without removing it
    function peek(LinkedQueue storage queue) internal view returns (bytes32) {
        require(queue.front != bytes32(0), "Queue is empty");
        return queue.front;
        
    }
    function getDocuments(LinkedQueue storage queue, uint256 lengthToBeFetched) internal view returns (bytes32[] memory) {
        // First, count the number of elements in the queue
        bytes32 current = queue.front;
        lengthToBeFetched = queue.length < lengthToBeFetched? queue.length: lengthToBeFetched;

        // Create the array with the correct size
        bytes32[] memory documents = new bytes32[](lengthToBeFetched);
        current = queue.front;
        uint256 index = 0;

        // Traverse the queue and fill the array
        while (current != bytes32(0)) {
            documents[index] = current;

            // Move to the next element
            current = queue.queueItems[current];
            index++;
        }

        return documents;
    }

    // Check if queue is empty
    function isEmpty(LinkedQueue storage queue) internal view returns (bool) {
        return queue.front == bytes32(0);
    }
}

contract DecentroLocker is Entities {

    mapping(address => User) user;
    mapping(address => UserRoles) public role;


    mapping(address => bytes32[]) DocumentArray;  // documents of each  user;
    mapping(bytes32 => Document) AllDocuments; // ipfs hash to document
    mapping(bytes32 => address) internal DocumentsVerifiedBy;

    //prototype for better queue

    using Queue for Queue.LinkedQueue;
    Queue.LinkedQueue private verifierQueue;
    Queue.LinkedQueue private adminQueue;



    User[] public allVerifiers;

    // Events
    event UserRegistered(address indexed userAddress, string firstName, string lastName);
    event UserEdited(address indexed  userAddress);
    event VerifierRegistered(address indexed verifierAddress, string firstName, string lastName);
    event VerifierEdited(address indexed userAddress);
    event DocumentUploaded(address indexed userAddress, string ipfsHash);
    event VerifiedByVerifier(address indexed verfierAddress, uint timestamp);
    event VerifiedByAdmin(uint timestamp);


    // Modifiers
    modifier onlyUser() {
        require(role[msg.sender] == UserRoles.User, "Not a User");
        _;
    }
    modifier onlyVerifier() {
        require(role[msg.sender] == UserRoles.Verifier, "Not a Verifier");
        _;
    }
    modifier onlyAdmin() {
        require(role[msg.sender] == UserRoles.Admin, "Not the Admin");
        _;
    }
    modifier onlyRecoverer() {
        require(role[msg.sender] == UserRoles.Recoverer, "Not a Recoverer");
        _;
    }

    function RegisterUser(
        string memory _firstName,
        string memory _lastName,
        string memory _email,
        string memory _mobile
    ) external {

        require(
        role[msg.sender] == UserRoles.Stranger,
        "User is already registered."
        );

        user[msg.sender] = User({
            firstName: _firstName,
            lastName: _lastName,
            walletAddress: msg.sender,
            email: _email,
            mobile: _mobile
        });

        role[msg.sender] = UserRoles.User;

        emit UserRegistered(msg.sender, _firstName, _lastName);
    }

    function EditUser(
        string memory _firstName,
        string memory _lastName,
        string memory _email,
        string memory _mobile
    ) external   {

        require(
        user[msg.sender].walletAddress == msg.sender,
        "User not authenticated to edit the details."
    );


    user[msg.sender].firstName = _firstName;
    user[msg.sender].lastName = _lastName;
    user[msg.sender].email = _email;
    user[msg.sender].mobile = _mobile;

    emit UserEdited(msg.sender);

   }


    function RegisterVerifier(
        string memory _firstName,
        string memory _lastName,
        string memory _email,
        string memory _mobile
    ) external  {
          require(
        role[msg.sender] == UserRoles.Stranger,
        "Verifier is already registered."
    );

        user[msg.sender] = User({
            firstName: _firstName,
            lastName: _lastName,
            email: _email,
            mobile: _mobile,
            walletAddress: msg.sender
        });

        allVerifiers.push(user[msg.sender]);
        role[msg.sender] = UserRoles.Verifier;

        emit VerifierRegistered(msg.sender, _firstName, _lastName);
    }

    function EditVerifier(
        string memory _firstName,
        string memory _lastName,
        string memory _email,
        string memory _mobile
        ) external   {

            require(
            role[msg.sender] == UserRoles.Admin || user[msg.sender].walletAddress == msg.sender,
            "Verifier not authenticated to edit the details."
        );

        user[msg.sender].firstName = _firstName;
        user[msg.sender].lastName = _lastName;
        user[msg.sender].email = _email;
        user[msg.sender].mobile = _mobile;

        emit VerifierEdited(msg.sender);
    }

    function RegisterAdmin(
        string memory _firstName,
        string memory _lastName,
        string memory _email,
        string memory _mobile
    ) external  {
          require(
        role[msg.sender] == UserRoles.Stranger,
        "Wallet address is already registered."
    );

        user[msg.sender] = User({
            firstName: _firstName,
            lastName: _lastName,
            email: _email,
            mobile: _mobile,
            walletAddress: msg.sender
        });
        role[msg.sender] = UserRoles.Verifier;

        emit VerifierRegistered(msg.sender, _firstName, _lastName);
    }

    function EditAdmin(
        string memory _firstName,
        string memory _lastName,
        string memory _email,
        string memory _mobile
        ) external   {

            require(
            role[msg.sender] == UserRoles.Admin || user[msg.sender].walletAddress == msg.sender,
            "Verifier not authenticated to edit the details."
        );

        user[msg.sender].firstName = _firstName;
        user[msg.sender].lastName = _lastName;
        user[msg.sender].email = _email;
        user[msg.sender].mobile = _mobile;

        emit VerifierEdited(msg.sender);
    }

//  mapping(address => string[]) DocumentArray;  // documents of each  user;
//     mapping(string => Document) AllDocuments; // ipfs hash to document
//     string[] toBeVerified; // contains all the to be verified docs 






    // *************** Doc upload ******************
    function uploadDocumentsByUser(string memory _ipfsHash, string memory _name) public onlyUser{
        Document memory userDoc = Document({
            name: _name,
            ipfsHash: _ipfsHash,
            status: DocumentStatus.Pending,
            verifiedBy: address(0),
            reason: "",
            timestamp: block.timestamp
        });
        bytes32 _ipfsHashEncoded = keccak256(abi.encodePacked(_ipfsHash));
        AllDocuments[_ipfsHashEncoded] = userDoc;
        DocumentArray[msg.sender].push(_ipfsHashEncoded);
        // toBeVerified.push(_ipfsHash);
        verifierQueue.enqueue(_ipfsHash);

    //    Docs[msg.sender].push((Document({
    //     name:_name,
    //     ipfsHash: _ipfsHash,
    //     status: DocumentStatus.Pending,
    //     timestamp: block.timestamp})));

        emit DocumentUploaded(msg.sender, _ipfsHash);
    }

    function getDocumentsByUser() public view onlyUser returns(Document[] memory){
        uint size = DocumentArray[msg.sender].length;
        Document[] memory AllDocsOfUser = new Document[](size);
        for(uint i=0; i<size; i++) {
            AllDocsOfUser[i] = AllDocuments[DocumentArray[msg.sender][i]];
        }
        return AllDocsOfUser;
        // User can categorise the documents in the frontend based on DocumentStatus
    }

    function DocumentVerificationByVerifier(bool verified, string memory _ipfsHash, string memory _reason) public onlyVerifier{
        bytes32 _ipfsHashEncoded = keccak256(abi.encodePacked(_ipfsHash));
        AllDocuments[_ipfsHashEncoded].status = verified? DocumentStatus.VerifierApproved: DocumentStatus.Rejected;
        AllDocuments[_ipfsHashEncoded].verifiedBy = msg.sender;
        verifierQueue.dequeue(_ipfsHash);
        if(verified) {
            adminQueue.enqueue(_ipfsHash);
        }
        else {
            AllDocuments[_ipfsHashEncoded].reason = _reason;
        }
        DocumentsVerifiedBy[_ipfsHashEncoded] = msg.sender;
        emit VerifiedByVerifier(msg.sender, block.timestamp);
    }

    function DocumentVerificationByAdmin(bool verified, string memory _ipfsHash, string memory _reason) public onlyAdmin {
        bytes32 _ipfsHashEncoded = keccak256(abi.encodePacked(_ipfsHash));
        AllDocuments[_ipfsHashEncoded].status = verified? DocumentStatus.AdminApproved: DocumentStatus.Rejected;
        AllDocuments[_ipfsHashEncoded].verifiedBy = msg.sender;
        adminQueue.dequeue(_ipfsHash);
        if(!verified) {
            AllDocuments[_ipfsHashEncoded].reason = _reason;
        }
        emit VerifiedByAdmin(block.timestamp);
    }



    // *****************temporary function to view the queue******************
    function GetQueue() public view returns (bytes32[] memory){
        bytes32[] memory currQueue = verifierQueue.getDocuments(100);
        return currQueue;
    }
    // ***********************************************************************

    function GetDocumentsByVerfier() public view onlyVerifier returns (Document[] memory) {
        bytes32[] memory currQueue = verifierQueue.getDocuments(100);
        uint256 size = currQueue.length;
        Document[] memory documentArrRes = new Document[](size);
        for(uint256 i=0; i<size; i++) {
            documentArrRes[i] = AllDocuments[currQueue[i]];
        }
        return documentArrRes;
    }

    function GetDocumentsByAdmin() public view onlyAdmin returns (Document[] memory) {
        bytes32[] memory currQueue = adminQueue.getDocuments(100);
        uint256 size = currQueue.length;
        Document[] memory documentArrRes = new Document[](size);
        for(uint256 i=0; i<size; i++) {
            documentArrRes[i] = AllDocuments[currQueue[i]];
        }
        return documentArrRes;
    }

    function getRole() public view returns (UserRoles) {
        return role[msg.sender];
    }

    function getUser() public view returns (User memory){
        return user[msg.sender];
    }

    function getAllverifiers() public view onlyAdmin returns (User[] memory){
        return allVerifiers;
    }


    // constructor 
    constructor(string memory _firstname, string memory _lastname, string memory _email, string memory _mobile, address _adminWalletAddress) {
        User memory admin = User({
            firstName: _firstname,
            lastName: _lastname,
            email: _email,
            mobile: _mobile,
            walletAddress: _adminWalletAddress
        });
        user[_adminWalletAddress] = admin;
        role[msg.sender] = UserRoles.Recoverer;
    }
}
