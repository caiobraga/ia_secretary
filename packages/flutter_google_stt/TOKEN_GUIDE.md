# Google Cloud Speech-to-Text Access Token Guide

This guide will help you generate an access token for the Google Cloud Speech-to-Text API.

## Prerequisites

1. **Google Cloud Project** with Speech-to-Text API enabled
2. **Service Account** with appropriate permissions
3. **Python 3.6+** installed on your system

## Step 1: Set Up Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the **Cloud Speech-to-Text API**:
   - Go to "APIs & Services" > "Library"
   - Search for "Cloud Speech-to-Text API"
   - Click "Enable"

## Step 2: Create Service Account

1. In Google Cloud Console, go to **IAM & Admin** > **Service Accounts**
2. Click **"Create Service Account"**
3. Fill in the details:
   - **Service account name**: `flutter-stt-service`
   - **Description**: `Service account for Flutter Speech-to-Text app`
4. Click **"Create and Continue"**
5. Add the following role:
   - **Cloud Speech Client** or **Cloud Speech Admin**
6. Click **"Continue"** and then **"Done"**

## Step 3: Create and Download Service Account Key

1. In the Service Accounts list, click on your newly created service account
2. Go to the **"Keys"** tab
3. Click **"Add Key"** > **"Create new key"**
4. Select **JSON** format
5. Click **"Create"** - this will download the JSON file
6. **Save this file securely** (e.g., `my-project-service-account.json`)

## Step 4: Install Required Python Libraries

```bash
pip install google-auth google-auth-oauthlib google-auth-httplib2
```

## Step 5: Generate Access Token

Run the token generation script:

```bash
cd /Users/nikhil/StudioProjects/flutter_google_stt
python generate_token.py path/to/your/service-account-key.json
```

### Example:
```bash
python generate_token.py ./my-project-service-account.json
```

## Step 6: Use the Access Token

1. Copy the generated access token
2. Use it in your Flutter app initialization:

```dart
await FlutterGoogleStt.initialize(
  accessToken: 'YOUR_GENERATED_ACCESS_TOKEN_HERE',
  languageCode: 'en-US',
);
```

## Important Notes

- **Access tokens expire** (usually after 1 hour)
- **Never commit** service account keys to version control
- **Keep your service account key secure**
- For production apps, consider using **Application Default Credentials** instead

## Troubleshooting

### "Import could not be resolved" error:
```bash
pip install --upgrade google-auth
```

### "Permission denied" error:
- Make sure your service account has the correct role
- Verify the Speech-to-Text API is enabled in your project

### "Invalid JSON" error:
- Ensure you downloaded the JSON key file correctly
- Check the file path is correct

## Alternative Method (Using gcloud CLI)

If you have `gcloud` CLI installed:

```bash
# Authenticate with your Google account
gcloud auth login

# Generate access token
gcloud auth print-access-token
```

## Security Best Practices

1. **Environment Variables**: Store tokens in environment variables
2. **Token Rotation**: Regenerate tokens regularly
3. **Minimal Permissions**: Use the least privilege principle
4. **Monitor Usage**: Check API usage in Google Cloud Console

---

Need help? Check the [Google Cloud Speech-to-Text documentation](https://cloud.google.com/speech-to-text/docs/quickstart-client-libraries).
