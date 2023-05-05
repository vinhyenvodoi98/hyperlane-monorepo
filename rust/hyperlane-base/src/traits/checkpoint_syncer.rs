use std::fmt::Debug;

use async_trait::async_trait;
use eyre::Result;

use hyperlane_core::{SignedAnnouncement, SignedCheckpoint, SignedCheckpointWithMessageId};

/// A generic trait to read/write Checkpoints offchain
#[async_trait]
pub trait CheckpointSyncer: Debug + Send + Sync {
    /// Read the highest index of this Syncer
    async fn latest_index(&self) -> Result<Option<u32>>;
    /// Attempt to fetch the signed checkpoint at this index
    async fn fetch_checkpoint(&self, index: u32) -> Result<Option<SignedCheckpoint>>;
    /// Attempt to fetch the signed (checkpoint, message id) tuple at this index
    async fn fetch_checkpoint_with_message_id(&self, index: u32) -> Result<Option<SignedCheckpointWithMessageId>>;
    /// Write the signed checkpoint to this syncer
    async fn write_checkpoint(&self, signed_checkpoint: &SignedCheckpoint) -> Result<()>;
    /// Write the signed (checkpoint, message id) tuple to this syncer
    async fn write_checkpoint_with_message_id(&self, signed_checkpoint: &SignedCheckpointWithMessageId) -> Result<()>;
    /// Write the signed announcement to this syncer
    async fn write_announcement(&self, signed_announcement: &SignedAnnouncement) -> Result<()>;
    /// Return the announcement storage location for this syncer
    fn announcement_location(&self) -> String;
}
