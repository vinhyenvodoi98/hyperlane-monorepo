// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

// ============ External Imports ============
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// ============ Internal Imports ============
import {IInterchainSecurityModule} from "../../interfaces/IInterchainSecurityModule.sol";
import {IMultisigIsm} from "../../interfaces/isms/IMultisigIsm.sol";
import {Message} from "../../libs/Message.sol";
import {MultisigIsmMetadata} from "../../libs/isms/MultisigIsmMetadata.sol";
import {CheckpointLib} from "../../libs/CheckpointLib.sol";
import {MerkleLib} from "../../libs/Merkle.sol";

/**
 * @title MultisigIsm
 * @notice Manages per-domain m-of-n Validator sets that are used to verify
 * interchain messages.
 */
abstract contract AbstractMultisigIsm is IMultisigIsm {
    // ============ Constants ============

    // solhint-disable-next-line const-name-snakecase
    uint8 public constant moduleType =
        uint8(IInterchainSecurityModule.Types.MULTISIG);

    // ============ Virtual Functions ============
    // ======= OVERRIDE THESE TO IMPLEMENT =======

    /**
     * @notice Returns the set of validators responsible for verifying _message
     * and the number of signatures required
     * @dev Can change based on the content of _message
     * @param _message Hyperlane formatted interchain message
     * @return validators The array of validator addresses
     * @return threshold The number of validator signatures needed
     */
    function validatorsAndThreshold(bytes calldata _message)
        public
        view
        virtual
        returns (address[] memory, uint8);

    // ============ Public Functions ============

    /**
     * @notice Requires that m-of-n validators verify a merkle root,
     * and verifies a merkle proof of `_message` against that root.
     * @param _metadata ABI encoded module metadata (see MultisigIsmMetadata.sol)
     * @param _message Formatted Hyperlane message (see Message.sol).
     */
    function verify(bytes calldata _metadata, bytes calldata _message)
        public
        view
        returns (bool)
    {
        bytes32 _digest = computeDigest(_metadata, _message);
        (
            address[] memory _validators,
            uint8 _threshold
        ) = validatorsAndThreshold(_message);
        require(_threshold > 0, "No MultisigISM threshold present for message");

        uint256 _validatorCount = _validators.length;
        uint256 _validatorIndex = 0;
        // Assumes that signatures are ordered by validator
        for (uint256 i = 0; i < _threshold; ++i) {
            address _signer = ECDSA.recover(
                _digest,
                MultisigIsmMetadata.signatureAt(_metadata, i)
            );
            // Loop through remaining validators until we find a match
            while (
                _validatorIndex < _validatorCount &&
                _signer != _validators[_validatorIndex]
            ) {
                ++_validatorIndex;
            }
            // Fail if we never found a match
            require(_validatorIndex < _validatorCount, "!threshold");
            ++_validatorIndex;
        }
        return true;
    }

    function computeDigest(bytes calldata _metadata, bytes calldata _message)
        internal
        pure
        returns (bytes32 digest)
    {
        bytes32 signedRoot;
        bytes32 signedMessageId;

        if (
            MultisigIsmMetadata.suffixType(_metadata) ==
            MultisigIsmMetadata.SuffixType.ROOT
        ) {
            signedRoot = MultisigIsmMetadata.root(_metadata);
            signedMessageId = Message.id(_message);
        } else {
            signedRoot = MerkleLib.branchRoot(
                Message.id(_message),
                MultisigIsmMetadata.proof(_metadata),
                Message.nonce(_message)
            );
            signedMessageId = MultisigIsmMetadata.id(_metadata);
        }

        digest = CheckpointLib.digest(
            Message.origin(_message),
            MultisigIsmMetadata.originMailbox(_metadata),
            signedRoot,
            MultisigIsmMetadata.index(_metadata),
            signedMessageId
        );
    }
}
