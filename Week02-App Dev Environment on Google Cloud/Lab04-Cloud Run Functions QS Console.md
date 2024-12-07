
## Cloud Run Functions: Qwik Start - Console

A Cloud Run function is a piece of code that runs in response to an event, such as an HTTP request, a message from a messaging service, or a file upload. Cloud events are things that happen in your cloud environment. These might be things like changes to data in a database, files added to a storage system, or a new virtual machine instance being created.

Since Cloud Run functions are event-driven, they only run when something happens. This makes them a good choice for tasks that need to be done quickly or that don't need to be running all the time.

For example, you can use a Cloud Run function to:
- Automatically generate thumbnails for images that are uploaded to Cloud Storage.
- Send a notification to a user's phone when a new message is received in Pub/Sub.
- Process data from a Cloud Firestore database and generate a report.

You can write your code in any language that supports Node.js, and you can deploy your code to the cloud with a few clicks. Once your Cloud Run function is deployed, it will automatically start running in response to events.

This hands-on lab shows you how to create, deploy, and test a Cloud Run function using the Google Cloud console.

## What you'll do
1. Create a Cloud Run function
2. Deploy and test the function
3. View logs

## Task 1: Create a function

In this step, you're going to create a Cloud Run function using the console.

1. In the console, on the **Navigation menu** click **VIEW ALL PRODUCTS**. In the **Serverless** section, click **Cloud Run functions**.
2. Click **Create function**.
3. In the **Create function** dialog, enter the following values:

| Field                        | Value                              |
|------------------------------|------------------------------------|
| **Environment**               | Cloud Run function                 |
| **Function name**             | GCFunction                         |
| **Region**                    | REGION                             |
| **Trigger type**              | HTTPS                              |
| **Authentication**            | Allow unauthenticated invocations |
| **Memory allocated**          | Keep it default                    |
| **Autoscaling**               | Set the Maximum number of instance to 5 and then click **Next** |

**Note**: A helpful popup may appear to validate the required APIs are enabled in the project. Click the **ENABLE** button when requested.

You will deploy the function in the next section.

## Task 2: Deploy the function

1. Still in the **Create function** dialog, in the **Source code for Inline editor**, use the default `helloHttp` function implementation already provided for `index.js`.
2. At the bottom, click **Deploy** to deploy the function.

**Note**: While the function is being deployed, the icon next to it is a small spinner. When it's deployed, the spinner changes to a green check mark.

### Test completed task
Click **Check my progress** to verify your performed task. If you have completed the task successfully, you will be granted an assessment score.

## Task 3: Test the function

Test the deployed function.

1. On the **function details dashboard**, to test the function, click on **TESTING**.
2. In the **Triggering event** field, enter the following text between the brackets `{}` and click **Test the function**:
   ```json
   {"message":"Hello World!"}
   ```
3. In the **Output** field, you should see the message **Hello World!**.
4. In the **Logs** field, a status code of `200` indicates success. (It may take a minute for the logs to appear).

A status code of `200` should display in the **Logs** field.

## Task 4: View logs

View logs from the Cloud Functions Overview page.

1. Click the blue arrow to go back to the **Cloud Run Functions Overview** page.
2. Display the menu for your function and click **View logs**.

### Example of the log history that displays in **Query results**:
- Your application is deployed, tested, and you can view the logs.

## Task 5: Test your understanding

Below are multiple-choice questions to reinforce your understanding of this lab's concepts. Answer them to the best of your abilities.

### 1. Cloud Run functions is a serverless execution environment for event-driven services on Google Cloud.  
- [ ] True  
- [ ] False  

### 2. Which type of trigger is used while creating Cloud Run functions in the lab?  
- [ ] Firebase  
- [ ] Pub/Sub  
- [x] HTTPS  
- [ ] Cloud Storage


For **Task 1: Create a function**, you need to create a Cloud Run function using the Google Cloud Console. There is no direct `gcloud` command for creating a Cloud Run function in the same way you would with a traditional Cloud Run service, but the creation process in the Console involves several UI steps. However, if you want to perform the task using the `gcloud` command line interface, you would typically follow this process:

1. **Write your function code** (e.g., `index.js`) and package it in a directory.
2. **Deploy the function** using the `gcloud functions deploy` command.


### Step 1: Write your function

Assume your function is a simple Node.js HTTP function. In `index.js`, you might have something like:

```js
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send('Hello World!');
});

app.listen(8080, () => {
  console.log('Function is listening on port 8080');
});
```

### Step 2: Create a `package.json` file

Make sure your `package.json` includes the necessary dependencies:

```json
{
  "name": "cloud-run-function",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.17.1"
  }
}
```

### Step 3: Deploy using the `gcloud` CLI

Now, deploy the function using the `gcloud` command.

1. **Build the container** for your function (if not using inline editor):
   
   Use Cloud Build to build a container image:

   ```bash
   gcloud builds submit --tag gcr.io/[PROJECT_ID]/cloud-run-function .
   ```

   Replace `[PROJECT_ID]` with your Google Cloud project ID.

2. **Deploy the Cloud Run function**:

   ```bash
   gcloud run deploy GCFunction \
     --image gcr.io/[PROJECT_ID]/cloud-run-function \
     --platform managed \
     --region [REGION] \
     --allow-unauthenticated \
     --max-instances 5
   ```

   - Replace `[PROJECT_ID]` with your Google Cloud project ID.
   - Replace `[REGION]` with the region where you want to deploy the function (e.g., `us-central1`).

### Step 4: Test the function

Once the deployment completes, you can test your function by navigating to the URL provided by the `gcloud` command. This URL will be displayed after deployment finishes, and you can use it to invoke your function.

---

This is the general flow using the `gcloud` CLI for deploying a Cloud Run service (which is essentially how you would deploy a Cloud Run function). If you're working through a specific lab, you may need to follow the UI-based steps in the Google Cloud Console instead.