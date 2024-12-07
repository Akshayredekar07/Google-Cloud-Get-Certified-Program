## Cloud Run Functions: Qwik Start - Command Line

### Objective

- Create a Cloud Run function
- Deploy and test the Cloud Run function
- View logs

## Task 1: Create a Function

1. **Set the Default Region**: In Cloud Shell, run the following command:

    ```bash
    gcloud config set run/region REGION
    ```

2. **Create a Directory for the Function Code**:

    ```bash
    mkdir gcf_hello_world && cd $_
    ```

3. **Create and Edit `index.js`**:

    ```bash
    nano index.js
    ```

4. **Add the Code to `index.js`**:

    ```javascript
    const functions = require('@google-cloud/functions-framework');

    // Register a CloudEvent callback with the Functions Framework that will
    // be executed when the Pub/Sub trigger topic receives a message.
    functions.cloudEvent('helloPubSub', cloudEvent => {
      // The Pub/Sub message is passed as the CloudEvent's data payload.
      const base64name = cloudEvent.data.message.data;

      const name = base64name
        ? Buffer.from(base64name, 'base64').toString()
        : 'World';

      console.log(`Hello, ${name}!`);
    });
    ```

5. **Exit Nano**: Press `Ctrl + X`, then `Y` to save.

6. **Create and Edit `package.json`**:

    ```bash
    nano package.json
    ```

7. **Add the Code to `package.json`**:

    ```json
    {
      "name": "gcf_hello_world",
      "version": "1.0.0",
      "main": "index.js",
      "scripts": {
        "start": "node index.js",
        "test": "echo \"Error: no test specified\" && exit 1"
      },
      "dependencies": {
        "@google-cloud/functions-framework": "^3.0.0"
      }
    }
    ```

8. **Exit Nano**: Press `Ctrl + X`, then `Y` to save.

9. **Install Dependencies**:

    ```bash
    npm install
    ```

---

## Task 2: Deploy Your Function

1. **Deploy the Function**:

    Deploy the Cloud Run function to a Pub/Sub topic named `cf-demo`.

    ```bash
    gcloud functions deploy nodejs-pubsub-function \
      --gen2 \
      --runtime=nodejs20 \
      --region=REGION \
      --source=. \
      --entry-point=helloPubSub \
      --trigger-topic cf-demo \
      --stage-bucket PROJECT_ID-bucket \
      --service-account cloudfunctionsa@PROJECT_ID.iam.gserviceaccount.com \
      --allow-unauthenticated
    ```

    **Note**: Replace `PROJECT_ID` and `REGION` with your project ID and preferred region.

2. **Verify the Deployment Status**:

    ```bash
    gcloud functions describe nodejs-pubsub-function \
      --region=REGION
    ```

    **Expected Output**:
    ```
    State: ACTIVE
    ```

---

## Task 3: Test the Function

1. **Publish a Message to the Pub/Sub Topic**:

    ```bash
    gcloud pubsub topics publish cf-demo --message="Cloud Function Gen2"
    ```

    **Expected Output**:
    ```
    messageIds:
    - '11927162971409664'
    ```

2. **Check Logs for the Execution**:

    View logs to confirm that your function was triggered successfully.

---

## Task 4: View Logs

1. **View Logs Using the `gcloud` Command**:

    ```bash
    gcloud functions logs read nodejs-pubsub-function --region=REGION
    ```

    **Expected Output**:
    ```
    LEVEL: I
    NAME: nodejs-pubsub-function
    EXECUTION_ID: h4v6akxf4sxt
    TIME_UTC: 2024-08-05 15:15:25.723
    LOG: Hello, Cloud Function Gen2!
    ```

    **Note**: Logs may take several minutes to appear.

2. **Alternative Way**: You can also go to **Logging > Logs Explorer** in the Google Cloud Console.

---

## Task 5: Test Your Understanding

Answer the following multiple-choice questions to reinforce your understanding of the lab's concepts:

1. **Serverless lets you write and deploy code without the hassle of managing the underlying infrastructure.**

    - True
    - False

