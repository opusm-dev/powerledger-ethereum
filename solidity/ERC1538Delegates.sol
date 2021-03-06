pragma solidity 0.5.1;
// pragma experimental "v0.5.0";

import "./ERC1538.sol";
import "./ERC1538Query.sol";
import "./UpgradeStorage.sol";

contract ERC1538Delegates is ERC1538, ERC1538Query, UpgradeStorage {
    
    constructor() public {
        contractOwner = msg.sender;
    }
    
    ////////////// ERC1538 ///////////////
    
    function updateContract(
        address _delegate, 
        string calldata _functionSignatures, 
        string calldata commitMessage
    ) external {
        require(msg.sender == contractOwner, "Must own the contract.");
        // pos is first used to check the size of the delegate contract.
        // After that pos is the current memory location of _functionSignatures.
        // It is used to move through the characters of _functionSignatures
        uint256 pos;
        if(_delegate != address(0)) {
            assembly {
                pos := extcodesize(_delegate)
            }
            require(pos > 0, "_delegate address is not a contract and is not address(0)");
        }
        // creates a bytes vesion of _functionSignatures
        bytes memory signatures = bytes(_functionSignatures);
        // stores the position in memory where _functionSignatures ends.
        uint256 signaturesEnd;
        // stores the starting position of a function signature in _functionSignatures
        uint256 start;
        assembly {
            pos := add(signatures,32)
            start := pos
            signaturesEnd := add(pos,mload(signatures))
        }
        // the function id of the current function signature
        bytes4 funcId;
        // the delegate address that is being replaced or address(0) if removing functions
        address oldDelegate;
        // the length of the current function signature in _functionSignatures
        uint256 num;
        // the current character in _functionSignatures
        uint256 char;
        // the position of the current function signature in the funcSignatures array
        uint256 index;
        // the last position in the funcSignatures array
        uint256 lastIndex;
        // parse the _functionSignatures string and handle each function
        for (; pos < signaturesEnd; pos++) {
            assembly {char := byte(0,mload(pos))}
            // 0x29 == )
            if (char == 0x29) {
                pos++;
                num = (pos - start);
                start = pos;
                assembly {
                    mstore(signatures,num)
                }
                funcId = bytes4(keccak256(signatures));
                oldDelegate = delegates[funcId];
                if(_delegate == address(0)) {
                    index = funcSignatureToIndex[signatures];
                    require(index != 0, "Function does not exist.");
                    index--;
                    lastIndex = funcSignatures.length - 1;
                    if (index != lastIndex) {
                        funcSignatures[index] = funcSignatures[lastIndex];
                        funcSignatureToIndex[funcSignatures[lastIndex]] = index + 1;
                    }
                    funcSignatures.length--;
                    delete funcSignatureToIndex[signatures];
                    delete delegates[funcId];
                    emit FunctionUpdate(funcId, oldDelegate, address(0), string(signatures));
                }
                else if (funcSignatureToIndex[signatures] == 0) {
                    require(oldDelegate == address(0), "FuncId clash.");
                    delegates[funcId] = _delegate;
                    funcSignatures.push(signatures);
                    funcSignatureToIndex[signatures] = funcSignatures.length;
                    emit FunctionUpdate(funcId, address(0), _delegate, string(signatures));
                }
                else if (delegates[funcId] != _delegate) {
                    delegates[funcId] = _delegate;
                    emit FunctionUpdate(funcId, oldDelegate, _delegate, string(signatures));

                }
                assembly {signatures := add(signatures,num)}
            }
        }
        emit CommitMessage(commitMessage);
    }
    
    ////////////// ERC1538 Query ///////////////
    
    function totalFunctions() external view returns(
        uint256
    ) {
        return funcSignatures.length;
    }

    function functionByIndex(
        uint256 _index
    ) external view returns(
        string memory functionSignature, 
        bytes4 functionId, 
        address delegate
    ) {
        require(_index < funcSignatures.length, "functionSignatures index does not exist.");
        bytes memory signature = funcSignatures[_index];
        functionId = bytes4(keccak256(signature));
        delegate = delegates[functionId];
        return (string(signature), functionId, delegate);
    }

    function functionExists(
        string calldata _functionSignature
    ) external view returns(
        bool
    ) {
        return funcSignatureToIndex[bytes(_functionSignature)] != 0;
    }

    function functionSignatures() external view returns(
        string memory
    ) {
        uint256 signaturesLength;
        bytes memory signatures;
        bytes memory signature;
        uint256 functionIndex;
        uint256 charPos;
        uint256 funcSignaturesNum = funcSignatures.length;
        bytes[] memory memoryFuncSignatures = new bytes[](funcSignaturesNum);
        for(; functionIndex < funcSignaturesNum; functionIndex++) {
            signature = funcSignatures[functionIndex];
            signaturesLength += signature.length;
            memoryFuncSignatures[functionIndex] = signature;
        }
        signatures = new bytes(signaturesLength);
        functionIndex = 0;
        for(; functionIndex < funcSignaturesNum; functionIndex++) {
            signature = memoryFuncSignatures[functionIndex];
            for(uint256 i = 0; i < signature.length; i++) {
                signatures[charPos] = signature[i];
                charPos++;
            }
        }
        return string(signatures);
    }

    function delegateFunctionSignatures(
        address _delegate
    ) external view returns(
        string memory
    ) {
        uint256 funcSignaturesNum = funcSignatures.length;
        bytes[] memory delegateSignatures = new bytes[](funcSignaturesNum);
        uint256 delegateSignaturesPos;
        uint256 signaturesLength;
        bytes memory signatures;
        bytes memory signature;
        uint256 functionIndex;
        uint256 charPos;
        for(; functionIndex < funcSignaturesNum; functionIndex++) {
            signature = funcSignatures[functionIndex];
            if(_delegate == delegates[bytes4(keccak256(signature))]) {
                signaturesLength += signature.length;
                delegateSignatures[delegateSignaturesPos] = signature;
                delegateSignaturesPos++;
            }

        }
        signatures = new bytes(signaturesLength);
        functionIndex = 0;
        for(; functionIndex < delegateSignatures.length; functionIndex++) {
            signature = delegateSignatures[functionIndex];
            if(signature.length == 0) {
                break;
            }
            for(uint256 i = 0; i < signature.length; i++) {
                signatures[charPos] = signature[i];
                charPos++;
            }
        }
        return string(signatures);
    }

    function delegateAddress(
        string calldata _functionSignature
    ) external view returns(
        address
    ) {
        require(funcSignatureToIndex[bytes(_functionSignature)] != 0, "Function signature not found.");
        return delegates[bytes4(keccak256(bytes(_functionSignature)))];
    }

    function functionById(
        bytes4 _functionId
    ) external view returns(
        string memory signature, 
        address delegate
    ) {
        for(uint256 i = 0; i < funcSignatures.length; i++) {
            if(_functionId == bytes4(keccak256(funcSignatures[i]))) {
                return (string(funcSignatures[i]), delegates[_functionId]);
            }
        }
        revert("functionId not found");
    }

    function delegateAddresses() external view returns(
        address[] memory
    ) {
        uint256 funcSignaturesNum = funcSignatures.length;
        address[] memory delegatesBucket = new address[](funcSignaturesNum);
        uint256 numDelegates;
        uint256 functionIndex;
        bool foundDelegate;
        address delegate;
        for(; functionIndex < funcSignaturesNum; functionIndex++) {
            delegate = delegates[bytes4(keccak256(funcSignatures[functionIndex]))];
            for(uint256 i = 0; i < numDelegates; i++) {
                if(delegate == delegatesBucket[i]) {
                    foundDelegate = true;
                    break;
                }
            }
            if(foundDelegate == false) {
                delegatesBucket[numDelegates] = delegate;
                numDelegates++;
            }
            else {
                foundDelegate = false;
            }
        }
        address[] memory delegates_ = new address[](numDelegates);
        functionIndex = 0;
        for(; functionIndex < numDelegates; functionIndex++) {
            delegates_[functionIndex] = delegatesBucket[functionIndex];
        }
        return delegates_;
    }
}
