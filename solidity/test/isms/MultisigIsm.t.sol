// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IMultisigIsm} from "../../contracts/interfaces/isms/IMultisigIsm.sol";
import {TestMailbox} from "../../contracts/test/TestMailbox.sol";
import {StaticMultisigIsmFactory} from "../../contracts/isms/multisig/StaticMultisigIsmFactory.sol";
import {MultisigIsmMetadata} from "../../contracts/libs/isms/MultisigIsmMetadata.sol";
import {CheckpointLib} from "../../contracts/libs/CheckpointLib.sol";
import {TypeCasts} from "../../contracts/libs/TypeCasts.sol";
import {Message} from "../../contracts/libs/Message.sol";
import {MOfNTestUtils} from "./IsmTestUtils.sol";

contract MultisigIsmTest is Test {
    using Message for bytes;

    uint32 constant ORIGIN = 11;
    StaticMultisigIsmFactory factory;
    IMultisigIsm ism;
    TestMailbox mailbox;

    function setUp() public {
        mailbox = new TestMailbox(ORIGIN);
        factory = new StaticMultisigIsmFactory();
    }

    function addValidators(
        uint8 m,
        uint8 n,
        bytes32 seed
    ) private returns (uint256[] memory) {
        uint256[] memory keys = new uint256[](n);
        address[] memory addresses = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 key = uint256(keccak256(abi.encode(seed, i)));
            keys[i] = key;
            addresses[i] = vm.addr(key);
        }
        ism = IMultisigIsm(factory.deploy(addresses, m));
        return keys;
    }

    function getMessage(
        uint32 destination,
        bytes32 recipient,
        bytes calldata body
    ) internal returns (bytes memory) {
        uint8 version = mailbox.VERSION();
        uint32 origin = mailbox.localDomain();
        bytes32 sender = TypeCasts.addressToBytes32(address(this));
        uint32 nonce = mailbox.count();
        mailbox.dispatch(destination, recipient, body);
        bytes memory message = Message.formatMessage(
            version,
            nonce,
            origin,
            sender,
            destination,
            recipient,
            body
        );
        return message;
    }

    function getMetadata(
        uint8 m,
        uint8 n,
        bytes32 seed,
        bytes memory message
    ) private returns (bytes memory) {
        uint32 domain = mailbox.localDomain();
        uint256[] memory keys = addValidators(m, n, seed);
        uint256[] memory signers = MOfNTestUtils.choose(m, keys, seed);
        bytes32 mailboxAsBytes32 = TypeCasts.addressToBytes32(address(mailbox));
        bytes32 checkpointRoot = mailbox.root();
        uint32 checkpointIndex = uint32(mailbox.count() - 1);
        bytes32 messageId = message.id();
        bytes32 digest = CheckpointLib.digest(
            domain,
            mailboxAsBytes32,
            checkpointRoot,
            checkpointIndex,
            messageId
        );
        MultisigIsmMetadata.SuffixType suffixType = MultisigIsmMetadata
            .SuffixType(uint8(uint256(seed) % 2));
        bytes memory metadata = abi.encodePacked(
            suffixType,
            checkpointIndex,
            mailboxAsBytes32
        );
        for (uint256 i = 0; i < m; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signers[i], digest);
            metadata = abi.encodePacked(metadata, r, s, v);
        }
        if (suffixType == MultisigIsmMetadata.SuffixType.ROOT) {
            metadata = abi.encodePacked(metadata, checkpointRoot);
        } else {
            metadata = abi.encodePacked(metadata, mailbox.proof(), messageId);
        }
        return metadata;
    }

    function testVerify(
        uint32 destination,
        bytes32 recipient,
        bytes calldata body,
        uint8 m,
        uint8 n,
        bytes32 seed
    ) public {
        vm.assume(0 < m && m <= n && n < 10);
        bytes memory message = getMessage(destination, recipient, body);
        bytes memory metadata = getMetadata(m, n, seed, message);
        assertTrue(ism.verify(metadata, message));
    }

    function testFailVerify(
        uint32 destination,
        bytes32 recipient,
        bytes calldata body,
        uint8 m,
        uint8 n,
        bytes32 seed
    ) public {
        vm.assume(0 < m && m <= n && n < 10);
        bytes memory message = getMessage(destination, recipient, body);
        bytes memory metadata = getMetadata(m, n, seed, message);

        // changing single bit in message ID or root should fail signature verification
        metadata[metadata.length - 1] = ~metadata[metadata.length - 1];
        ism.verify(metadata, message);
    }
}
