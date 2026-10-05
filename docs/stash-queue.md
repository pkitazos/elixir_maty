# Message Ordering and Protocol Adherence

In Maty, the runtime maintains a queue for each established session. Each queue contains messages structured as `<q, r, l(v)>`, following the same notation defined above. Maty includes a structural congruence rule on queues that allows reordering of unrelated messages while preserving message order between pairs of participants.

In our implementation, we use actor mailboxes as queues for handling messages, which do not allow the same fine-grained message reordering. In our work, messages are structured as `<s, q, r, l(v)>`. While this structure provides enough information to represent Maty's message states, it lacks the ability to reorder messages within the mailbox.

In a naive implementation out-of-order messages are simply buffered by sending them to the back of the mailbox queue. However, this approach is susceptible to the following subtle issue. Consider the following global protocol with three participants `P`, `Q`, and `R`:
```
P->Q:a(Int). R->Q:b(Int). R->Q:b(Int). P->Q:a(Int)
```
The global type gives us this local session type for participant Q:
```
Q := P&a(Int). R&b(Int). R&b(Int). P&a(Int)
```
Let us assume `P` sends the values 10 and 20, while `R` sends 5 and 15, in that order. Our framework's session typechecking ensures that each participant sends messages in the correct order and the BEAM runtime guarantees that messages from the same process are always received in the order they were sent. However, there is no guarantee about the order in which messages from different participants are interleaved in `Q`'s mailbox. As a result, `Q` could receive the messages in this order (we omit `s` and `Q` as they would be the same in all messages):

```
[<R, b(5)>, <P, a(10)>, <P, a(20)>, <R, b(15)>]
```

If `Q` simply buffers unexpected messages by moving them to the back of its mailbox queue, it will process the messages in the following order:

```
[<P, a(10)>, <R, b(15)>, <R, b(5)>, <P, a(20)>]
```

This leads to processing `b(15)` before `b(5)`, violating the ordering guarantee for `R`'s messages.

To address the limitations of the naive buffering approach, we introduce a separate internal queue: the stash. The stash is used to store messages that arrive out of order, allowing the actor to process messages according to the session type and maintain the sender's ordering.

The stash queue is always checked first when looking for the next expected message. If a matching message is found in the stash, it is processed, and the actor continues with the next step in the session type. Otherwise, the actor falls back to checking the mailbox queue.

When a message arrives that doesn't match the expected session type, instead of buffering it in the mailbox queue, the actor moves the message to the stash. This ensures the relative order of messages from any given sender is maintained, even when arriving out of order with respect to other senders' messages.

Let us look at a step-by-step example of how the stash queue approach works, using the same global protocol and message sequence as before.

1. `Q` expects a message from `P` with label `a`. It checks the stash queue, which is empty, so it looks at the mailbox queue and finds `<R, b(5)>`. Since this doesn't match the expected message, `Q` moves it to the stash queue.

2. `Q` checks the mailbox queue again and finds `<P, a(10)>`, matching the expected message. It processes this message and updates its type to expect a message from `R` with label `b`.

3. `Q` checks the stash and finds `<R, b(5)>`, which matches the expected message. It processes this message and updates its session type to expect another message from R with label `b`.

4. `Q` checks the stash, which is now empty, so it looks at the mailbox queue and finds `<P, a(20)>`. Since this doesn't match the expected message, `Q` moves it to the stash queue.

5. `Q` checks the mailbox queue again and finds `<R, b(15)>`, matching the expected message. It processes this message and updates its type to expect a message from `P` with label `a`.

6. `Q` checks the stash and finds `<P, a(20)>`, which matches the expected message. It processes this message, and the session is now complete.

Using the stash queue, the actor with role `Q` is able to process all messages in the correct order, maintaining both the order within each sender's message sequence and the overall session type structure.

# Message re-ordering inductive proof

In general, we can establish the correctness of our stash-based approach through an invariant: at each receive step, for any pair of messages `m1`, `m2` sent by the same sender where `m1` was sent before `m2`, either `m1` is positioned in the stash ahead of `m2`, or `m1` has already been processed. This guarantees `m2` is never processed before `m1`. This property can be proven through induction:
- Base case: Before any messages are received, the invariant holds trivially since no messages have been processed and the stash queue is empty.
- Inductive step: When handling a new message m, one of two scenarios occurs:
    - If m matches the expected message type and sender, it is processed immediately (either from the stash or mailbox), maintaining the invariant.
    - If m does not match expectations, it moves to the stash queue, preserving the relative order of messages from the same sender.
