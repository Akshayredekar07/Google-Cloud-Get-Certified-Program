
## Pub/Sub: Qwik Start - Console

**Overview**  
Pub/Sub is a messaging service for exchanging event data among applications and services. A producer of data publishes messages to a Pub/Sub topic. A consumer creates a subscription to that topic. Subscribers either pull messages from a subscription or are configured as webhooks for push subscriptions. Every subscriber must acknowledge each message within a configurable window of time.

### What You'll Learn:
- Set up a topic to hold data.
- Subscribe to a topic to access the data.
- Publish and then consume messages with a pull subscriber.

## Task 1: Setting Up Pub/Sub

To use Pub/Sub, you'll create a **topic** and **subscription**:

1. From the **Navigation Menu**, go to **Analytics > Pub/Sub > Topics**.
2. Click **Create Topic**.
3. In the **Create a Topic** dialog:
   - For **Topic ID**, type `MyTopic`.
   - Leave the other fields at default.
4. Click **Create**.

**Test Completed Task**  
Click **Check my progress** to verify if you've successfully created a Cloud Pub/Sub topic.

## Task 2: Add a Subscription

1. In the **Topics** section, click on the three-dot icon next to `MyTopic` and select **Create Subscription**.
2. In the **Add Subscription to Topic** dialog:
   - Name the subscription (e.g., `MySub`).
   - Set **Delivery Type** to **Pull**.
3. Click **Create**.

**Test Completed Task**  
Click **Check my progress** to verify if you’ve successfully created a subscription.

## Task 3: Test Your Understanding

Answer these questions to reinforce your knowledge:

1. **A publisher application creates and sends messages to a ____. Subscriber applications create a ____ to a topic to receive messages from it.**
   - subscription, topic
   - topic, subscription
   - subscription, subscription
   - topic, topic

2. **Cloud Pub/Sub is an asynchronous messaging service designed to be highly reliable and scalable.**
   - True
   - False


## Task 4: Publish a Message to the Topic

1. Navigate to **Pub/Sub > Topics** and open the `MyTopic` page.
2. In the **Messages** tab, click **Publish Message**.
3. Enter `Hello World` in the **Message** field and click **Publish**.


## Task 5: View the Message

1. Use the subscription `MySub` to pull the message from the topic `MyTopic`.  
2. In Cloud Shell, run the following command:

   ```bash
   gcloud pubsub subscriptions pull --auto-ack MySub
   ```

   The message will appear in the `DATA` field of the output.
