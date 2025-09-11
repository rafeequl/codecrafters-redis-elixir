# BLPOP Black Box Test Plan

## Test Environment Setup
- Redis clone server running on localhost:6379
- Multiple client connections for concurrent testing
- Clean state before each test (FLUSHALL)

## Test Categories

### 1. Basic Functionality Tests

#### Test 1.1: Immediate Pop from Non-Empty List
**Objective**: Verify BLPOP returns immediately when list has items
**Steps**:
1. RPUSH "test_list" "item1" "item2"
2. BLPOP "test_list" "5"
**Expected**: Returns ["test_list", "item1"] immediately
**Verification**: List contains only "item2"

#### Test 1.2: Pop from Empty List (Blocking)
**Objective**: Verify BLPOP blocks when list is empty
**Steps**:
1. BLPOP "empty_list" "2" (in background process)
2. Wait 100ms
3. RPUSH "empty_list" "item1"
**Expected**: Returns ["empty_list", "item1"] after RPUSH
**Verification**: List becomes empty after pop

### 2. Timeout Behavior Tests

#### Test 2.1: Integer Timeout
**Objective**: Verify integer timeout conversion (seconds to milliseconds)
**Steps**:
1. Start timer
2. BLPOP "timeout_list" "1"
3. Stop timer
**Expected**: Returns nil after ~1000ms
**Verification**: Elapsed time ≥ 900ms and ≤ 1200ms

#### Test 2.2: Float Timeout
**Objective**: Verify float timeout conversion
**Steps**:
1. Start timer
2. BLPOP "timeout_list" "0.5"
3. Stop timer
**Expected**: Returns nil after ~500ms
**Verification**: Elapsed time ≥ 400ms and ≤ 700ms

#### Test 2.3: Zero Timeout (Infinite Wait)
**Objective**: Verify timeout=0 means infinite wait
**Steps**:
1. BLPOP "infinite_list" "0" (in background)
2. Wait 2 seconds
3. RPUSH "infinite_list" "item1"
**Expected**: Returns ["infinite_list", "item1"] after RPUSH
**Verification**: No timeout occurs

### 3. Concurrent Client Tests

#### Test 3.1: Multiple Clients Waiting
**Objective**: Verify FIFO ordering of waiting clients
**Steps**:
1. Start Client A: BLPOP "multi_list" "5"
2. Start Client B: BLPOP "multi_list" "5"
3. Start Client C: BLPOP "multi_list" "5"
4. RPUSH "multi_list" "item1"
5. RPUSH "multi_list" "item2"
6. RPUSH "multi_list" "item3"
**Expected**: 
- Client A gets ["multi_list", "item1"]
- Client B gets ["multi_list", "item2"] 
- Client C gets ["multi_list", "item3"]
**Verification**: All clients receive items in order

#### Test 3.2: Client Timeout During Wait
**Objective**: Verify timeout removes client from waiting queue
**Steps**:
1. Start Client A: BLPOP "timeout_queue" "1"
2. Start Client B: BLPOP "timeout_queue" "3"
3. Wait 1.5 seconds (Client A times out)
4. RPUSH "timeout_queue" "item1"
**Expected**: Only Client B receives ["timeout_queue", "item1"]
**Verification**: Client A returns nil, Client B gets item

### 4. Edge Cases Tests

#### Test 4.1: Non-Existent Key
**Objective**: Verify BLPOP on non-existent key blocks
**Steps**:
1. BLPOP "nonexistent" "1" (in background)
2. Wait 100ms
3. RPUSH "nonexistent" "item1"
**Expected**: Returns ["nonexistent", "item1"] after RPUSH
**Verification**: Key created and item popped

#### Test 4.2: Key Type Mismatch
**Objective**: Verify BLPOP on non-list key behavior
**Steps**:
1. SET "string_key" "value"
2. BLPOP "string_key" "1"
**Expected**: Error or nil (implementation dependent)
**Verification**: String key unchanged

#### Test 4.3: Empty String Timeout
**Objective**: Verify empty timeout string handling
**Steps**:
1. BLPOP "test_list" ""
**Expected**: Error or default timeout behavior
**Verification**: Appropriate error response

### 5. Race Condition Tests

#### Test 5.1: Simultaneous BLPOP and RPUSH
**Objective**: Verify atomicity between blocking and pushing
**Steps**:
1. Start 10 concurrent BLPOP clients on "race_list"
2. Simultaneously RPUSH 10 items to "race_list"
**Expected**: All 10 clients receive items, no duplicates
**Verification**: List becomes empty, all clients get unique items

#### Test 5.2: BLPOP During List Modification
**Objective**: Verify BLPOP works during other list operations
**Steps**:
1. RPUSH "modify_list" "item1" "item2"
2. Start BLPOP "modify_list" "2" (in background)
3. Simultaneously: LPUSH "modify_list" "item0"
4. Simultaneously: LPOP "modify_list"
**Expected**: BLPOP gets one of the available items
**Verification**: List state consistent after operations

### 6. Performance Tests

#### Test 6.1: High Concurrency
**Objective**: Verify performance with many waiting clients
**Steps**:
1. Start 100 BLPOP clients on "perf_list"
2. Measure time to RPUSH 100 items
3. Measure time for all clients to receive items
**Expected**: All clients receive items within reasonable time
**Verification**: Total time < 5 seconds

#### Test 6.2: Memory Usage
**Objective**: Verify waiting queue cleanup
**Steps**:
1. Start 50 BLPOP clients with short timeout
2. Wait for all timeouts
3. Check server memory/state
**Expected**: Waiting queues cleaned up properly
**Verification**: No memory leaks in waiting queues

### 7. Error Handling Tests

#### Test 7.1: Invalid Timeout Format
**Objective**: Verify error handling for invalid timeouts
**Steps**:
1. BLPOP "test_list" "abc"
2. BLPOP "test_list" "-1"
3. BLPOP "test_list" "1.5.2"
**Expected**: Appropriate error responses
**Verification**: Server remains stable

#### Test 7.2: Client Disconnection During Wait
**Objective**: Verify cleanup when client disconnects
**Steps**:
1. Start BLPOP client
2. Force disconnect client
3. RPUSH to the list
**Expected**: No hanging processes or memory leaks
**Verification**: Server state clean

### 8. Integration Tests

#### Test 8.1: BLPOP with Other List Commands
**Objective**: Verify BLPOP works with other list operations
**Steps**:
1. RPUSH "integration_list" "item1" "item2" "item3"
2. BLPOP "integration_list" "1"
3. LPUSH "integration_list" "item0"
4. LRANGE "integration_list" "0" "-1"
**Expected**: BLPOP pops "item1", LPUSH adds "item0" to front
**Verification**: Final list is ["item0", "item2", "item3"]

#### Test 8.2: BLPOP with Expiration
**Objective**: Verify BLPOP behavior with TTL
**Steps**:
1. RPUSH "ttl_list" "item1"
2. EXPIRE "ttl_list" "2"
3. Wait 1 second
4. BLPOP "ttl_list" "5"
**Expected**: Returns item before expiration
**Verification**: Key expires after TTL

## Test Execution Notes

- Use separate processes for concurrent BLPOP operations
- Implement proper cleanup between tests
- Monitor server logs for errors
- Verify RESP protocol compliance in responses
- Test with various data types and sizes
- Include stress testing with high load

## Success Criteria

- All blocking operations complete within expected timeframes
- No memory leaks or hanging processes
- Proper FIFO ordering of waiting clients
- Correct timeout behavior for all timeout formats
- Graceful handling of edge cases and errors
- Consistent behavior under concurrent load
