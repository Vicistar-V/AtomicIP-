# Batch Swap Approval Testing (#504)

## Overview

The batch swap approval testing suite validates the multi-signature approval mechanism for batch swaps. This feature allows multiple parties to approve a swap before it progresses from `Pending` to `Accepted` status.

## Test Coverage

### 1. Single Approval
**File**: `batch_approval_tests.rs::test_batch_approve_single_approval`

Validates that a single approver can successfully approve a swap with `required_approvals = 1`.

- **Setup**: Initiates a batch with 1 swap requiring 1 approval
- **Action**: Approves the swap with one approver
- **Verification**: Swap approvals contain exactly 1 entry with the correct approver address

### 2. Multiple Approvers
**File**: `batch_approval_tests.rs::test_batch_approve_multiple_approvers`

Validates that multiple distinct approvers can approve the same swap sequentially.

- **Setup**: Initiates a batch with 1 swap requiring 3 approvals
- **Action**: Submits 3 approvals from different addresses
- **Verification**: 
  - All 3 approvals are tracked in order
  - Each approver address appears exactly once
  - Approval count matches expected value

### 3. Duplicate Prevention
**File**: `batch_approval_tests.rs::test_batch_approve_prevents_duplicate`

Ensures that the same approver cannot approve a swap twice.

- **Setup**: Initiates a batch with 1 swap requiring 2 approvals
- **Action**: Attempts to submit 2 approvals from the same address
- **Verification**: Second approval from same address panics with `AlreadyApproved` error

### 4. Status Constraints
**File**: `batch_approval_tests.rs::test_batch_approve_only_pending`

Validates that only swaps in `Pending` status can receive approvals.

- **Setup**: Initiates a batch and advances it to `Accepted` status
- **Action**: Attempts to approve the now-Accepted swap
- **Verification**: Operation fails with `NotPending` error

### 5. Batch Multi-Swap Approvals
**File**: `batch_approval_tests.rs::test_batch_approve_multiple_swaps`

Validates that approvals are independently tracked across multiple swaps in a batch.

- **Setup**: Initiates a batch with 3 swaps
- **Action**: Approves each swap with the same approver
- **Verification**: 
  - Each swap maintains independent approval records
  - All swaps show exactly 1 approval from the same approver
  - No cross-swap approval contamination

### 6. Approvals Persist Post-Completion
**File**: `batch_approval_tests.rs::test_batch_approve_clears_on_completion`

Validates that approval records persist after a swap completes.

- **Setup**: Initiates, approves, accepts, and completes a swap
- **Action**: Queries approval history post-completion
- **Verification**: Approvals remain accessible after swap transitions to `Completed`

### 7. Empty Approvals Query
**File**: `batch_approval_tests.rs::test_batch_approve_get_approvals_empty`

Validates that querying approvals for a newly-initiated swap returns an empty vector.

- **Setup**: Initiates a batch
- **Action**: Queries approvals immediately after initiation
- **Verification**: Returns empty vector (no approvals yet)

## Integration Points

### Contract Methods Tested

- `batch_initiate_swap()` - Initiates batch with approval requirements
- `approve_swap()` - Records individual approval
- `get_swap_approvals()` - Retrieves approval list for a swap
- `batch_accept_swaps()` - Validates approval threshold before accepting
- `batch_reveal_keys()` - Final approval validation during completion

### Data Structures

- `DataKey::SwapApprovals(u64)` - Storage key for swap approval vectors
- `SwapApprovedEvent` - Published when approval is recorded
- `SwapRecord::required_approvals` - Field defining approval threshold

## Test Patterns

All tests follow this structure:

1. **Setup Phase**: Registry, token, and contract initialization
2. **IP Commitment**: Create and commit IP assets
3. **Batch Initiation**: Create batch swaps with approval requirements
4. **Approval Operations**: Submit approvals and query state
5. **Verification**: Assert expected approval state and events

## Error Cases Tested

| Error | Test | Expected Behavior |
|-------|------|-------------------|
| `AlreadyApproved` | test_batch_approve_prevents_duplicate | Duplicate approvals blocked |
| `NotPending` | test_batch_approve_only_pending | Only Pending swaps can be approved |
| `BatchEmpty` | Covered by framework | Empty batch initiations fail |

## Future Enhancements

- Threshold-based approval progression (automatic state transition at threshold)
- Approval timeout and expiry
- Approval revocation/cancellation
- Role-based approval requirements (e.g., seller + independent auditor)
