# Kafka KRaft raft IO fault runbook

## Symptom

Kafka exits with a fatal KRaft raft IO thread error similar to:

```text
Encountered fatal fault: Unexpected error in raft IO thread
java.lang.IllegalStateException: Received request or response with leader OptionalInt[3]
and epoch 17 which is inconsistent with current leader OptionalInt.empty and epoch 0
```

## Meaning

The local controller's KRaft metadata log believes it is at epoch `0` and has no
known leader, but it received a raft message from the quorum that identifies
controller `3` as leader at epoch `17`. Kafka treats that divergence as fatal to
avoid processing metadata with an unsafe or contradictory view of quorum
leadership.

This usually means the node is not reading the same KRaft state as the rest of
the controller quorum. The common causes are:

- `node.id` reused by more than one Kafka process.
- A controller node was started with an empty, stale, or different
  `metadata.log.dir` / `log.dirs` volume.
- `controller.quorum.voters` differs across controllers, references the wrong
  host or port, or omits one of the controller voters.
- Controller and broker node IDs overlap in a split-role deployment.
- A node was formatted with a different cluster ID, or is accidentally pointed
  at another Kafka cluster.
- Network or DNS routes a controller listener to the wrong process.
- Running a Kafka version with a known KRaft raft bug; for example, Apache Kafka
  PR 16900 fixed a resigned-state leader notification issue in upstream Kafka.

## Checks before deleting state

Collect the following from every controller node:

```bash
kafka-storage.sh info --config /path/to/server.properties
```

Then compare these settings across all controllers:

```properties
process.roles
node.id
controller.listener.names
listeners
advertised.listeners
controller.quorum.voters
metadata.log.dir
log.dirs
```

Expected invariants:

- Every Kafka process has a unique `node.id`.
- In a dedicated-controller deployment, controller IDs and broker IDs are
  distinct.
- Every controller has the same `controller.quorum.voters` set.
- The `node.id` of each controller appears exactly once in
  `controller.quorum.voters`.
- Listener hosts and ports in `controller.quorum.voters` resolve to controller
  listeners, not broker listeners.
- All nodes report the same cluster ID from `kafka-storage.sh info`.
- Persistent volumes are mounted at the paths Kafka is actually using for the
  metadata log.

## Recovery guidance

1. Stop the failing Kafka process.
2. Fix any configuration mismatch found above.
3. If the node's metadata directory is empty, stale, or formatted for the wrong
   cluster, do not blindly delete all Kafka data. First identify whether the
   node is a controller-only node or a combined broker/controller.
4. For a controller-only node that lost local KRaft state while a majority of
   the controller quorum is healthy, reformat only that node's controller
   metadata storage with the existing cluster ID, then restart it so it can
   catch up from the quorum.
5. For combined broker/controller nodes, preserve broker log data unless you
   intentionally plan to replace that broker. Reformatting or deleting `log.dirs`
   can remove partition data.
6. If no controller quorum majority is healthy, restore the metadata log from
   backup or follow Kafka's documented quorum recovery procedure for the version
   in use.
7. After restart, verify quorum health:

```bash
kafka-metadata-quorum.sh --bootstrap-controller <host:controller-port> describe --status
kafka-metadata-quorum.sh --bootstrap-controller <host:controller-port> describe --replication
```

## Version follow-up

If configuration and storage are correct, check the exact Kafka distribution and
version. Search the release notes for KRaft fixes around raft leader changes and
resigned controller state, and upgrade to a version containing those fixes.
