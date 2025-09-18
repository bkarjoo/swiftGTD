# FastGTD API Quickstart Guide

## Overview
FastAPI backend with JWT authentication, nodes (tasks/notes/folders/smart folders/templates), and file attachments ("artifacts").

## Base URL Configuration

Set once and reuse in all examples:

```bash
# If using start.sh
export API_BASE=http://127.0.0.1:8003

# If using uvicorn directly
export API_BASE=http://127.0.0.1:8000

# For SwiftGTD app
# Prefer Info.plist key `API_BASE_URL` or env var at runtime
# DEBUG fallback (if unset): http://localhost:8003
```

## Live API Documentation

- **Swagger UI**: `${API_BASE}/docs`
- **ReDoc**: `${API_BASE}/redoc`
- **OpenAPI JSON**: `${API_BASE}/openapi.json`

## Authentication Flow

### 1. Signup
```bash
# DO NOT use real credentials in documentation!
POST ${API_BASE}/auth/signup
Body: {
  "email": "user@example.com",
  "password": "CHANGE_THIS_PASSWORD",
  "full_name": "John Doe"
}
```

### 2. Login
```bash
# Example only - use your own credentials
POST ${API_BASE}/auth/login
Body: {
  "email": "user@example.com",
  "password": "YOUR_PASSWORD_HERE"
}
Response: {
  "access_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

### 3. Authentication Header
All authenticated requests must include:
```
Authorization: Bearer <access_token>
```

### JavaScript Login Example
```javascript
const res = await fetch(`${API_BASE}/auth/login`, {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({ email, password })
});
const { access_token } = await res.json();
```

## Health Check

```bash
GET ${API_BASE}/health
Response: { "status": "ok" }
```

## Nodes API (Core Data)

Base path: `${API_BASE}/nodes`

### Create Task
```bash
POST /nodes/
Body: {
  "title": "My Task",
  "node_type": "task",
  "task_data": {
    "status": "todo",
    "priority": "medium",
    "description": "Task description"
  }
}
```

### Create Note
```bash
POST /nodes/
Body: {
  "title": "Note Title",
  "node_type": "note",
  "note_data": {
    "body": "# Markdown or text content"
  },
  "parent_id": "<uuid-optional>"
}
```

### Create Folder
```bash
POST /nodes/
Body: {
  "title": "My Folder",
  "node_type": "folder",
  "parent_id": "<uuid-optional>"
}
```

### List Nodes (with optional filters)
```bash
GET /nodes/?parent_id=<uuid>&node_type=task|note|folder|smart_folder|template&search=foo&limit=50&offset=0
```

### Get Single Node
```bash
GET /nodes/{id}
```

### Update Node
```bash
PUT /nodes/{id}

# Task example
Body: {
  "title": "Updated Title",
  "task_data": {
    "status": "done",
    "completed_at": "2025-09-14T12:00:00Z"
  }
}

# Note example
Body: {
  "note_data": {
    "body": "Updated markdown content"
  }
}
```

### Delete Node
```bash
DELETE /nodes/{id}
```

### Toggle Task Completion (SwiftGTD specific)
```bash
PUT /nodes/{id}
Body: {
  "task_data": {
    "status": "done",  # or "todo"
    "completed_at": "2025-09-14T12:00:00Z"  # or null
  }
}
```

## Artifacts API (File Uploads)

### Upload File to Node
```bash
POST ${API_BASE}/artifacts
Content-Type: multipart/form-data

Form fields:
- node_id: <target-node-uuid>
- file: <file-contents>

Response (201 Created): {
  "id": "artifact-uuid",
  "node_id": "node-uuid",
  "filename": "stored-name.pdf",
  "original_filename": "MyDocument.pdf",
  "mime_type": "application/pdf",
  "size_bytes": 102400,
  "created_at": "2025-09-14T12:00:00Z"
}
```

### Download Artifact
```bash
GET ${API_BASE}/artifacts/{artifact_id}/download
Returns: File binary data
```

### List Node's Artifacts
```bash
GET ${API_BASE}/artifacts/node/{node_id}
Returns: Array of artifact objects
```

### Delete Artifact
```bash
DELETE ${API_BASE}/artifacts/{artifact_id}
```

### JavaScript Upload Example
```javascript
const fd = new FormData();
fd.append('node_id', nodeId);
fd.append('file', fileInput.files[0]);

const response = await fetch(`${API_BASE}/artifacts`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`
  },
  body: fd
});
```

## Request Headers

### JSON Requests
```javascript
{
  'Content-Type': 'application/json',
  'Authorization': 'Bearer <token>'
}
```

### Multipart/File Upload
```javascript
{
  'Authorization': 'Bearer <token>'
  // Don't set Content-Type - let browser set it with boundary
}
```

## Common Error Codes

- **401 Unauthorized**: `{ "detail": "invalid_token" }` - Missing or invalid auth token
- **404 Not Found**: `{ "detail": "Node not found" }` or `{ "detail": "Artifact not found" }`
- **400 Bad Request**: Validation errors (e.g., invalid smart folder rules)
- **422 Unprocessable Entity**: Invalid request body structure

## Node Types and Their Data

### Task
```json
{
  "node_type": "task",
  "task_data": {
    "status": "todo" | "in_progress" | "done",
    "priority": "low" | "medium" | "high",
    "description": "string",
    "due_date": "2025-09-14T12:00:00Z",
    "completed_at": "2025-09-14T12:00:00Z"
  }
}
```

### Note
```json
{
  "node_type": "note",
  "note_data": {
    "body": "Markdown or plain text content"
  }
}
```

### Folder
```json
{
  "node_type": "folder"
  // No additional data required
}
```

### Smart Folder
```json
{
  "node_type": "smart_folder",
  "smart_folder_data": {
    "rules": {
      "node_type": "task",
      "status": "todo"
    }
  }
}
```

### Template
```json
{
  "node_type": "template",
  "template_data": {
    "template_type": "project" | "checklist",
    "content": {}
  }
}
```

## SwiftGTD Integration Notes

The SwiftGTD app uses this API with the following specifics:

1. **Base URL**: Configurable via Info.plist key `API_BASE_URL` or environment variable `API_BASE_URL`. In DEBUG builds, if unset, defaults to `http://localhost:8003`. In Release, a missing value will cause a fatal error.
2. **Authentication**: Token stored in UserDefaults as `auth_token`
3. **Main Endpoints Used**:
   - `GET /auth/me` - Check authentication status
   - `GET /nodes/?limit=1000` - Load all nodes
   - `PUT /nodes/{id}` - Toggle task completion
   - `DELETE /nodes/{id}` - Delete nodes

## Development Tips

1. **Generate Client SDK**: Use `${API_BASE}/openapi.json` with OpenAPI Generator or Swagger Codegen
2. **CORS**: Enabled for local development; prefer same-origin or configured origins in production
3. **Response Types**: Node responses vary by `node_type` - inspect schemas in Swagger UI
4. **Testing**: Use the Swagger UI at `/docs` for interactive API testing
5. **Debugging**: Check server logs for detailed error messages

## Quick Test Commands

```bash
# Health check
curl ${API_BASE}/health

# Login (save the token) - Replace with your credentials
TOKEN=$(curl -X POST ${API_BASE}/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"YOUR_EMAIL@example.com","password":"YOUR_PASSWORD"}' \
  | jq -r .access_token)

# Get all nodes
curl ${API_BASE}/nodes/?limit=10 \
  -H "Authorization: Bearer $TOKEN"

# Create a task
curl -X POST ${API_BASE}/nodes/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Task","node_type":"task"}'
```
