# API Reference

## Node Types

SwiftGTD supports five node types, each with specific fields and behaviors:

### Common Fields (All Nodes)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | Yes | Unique identifier |
| `title` | String | Yes | Node title (max 255 chars) |
| `node_type` | String | Yes | Type: folder, task, note, template, smart_folder |
| `parent_id` | UUID | No | Parent node ID |
| `owner_id` | UUID | Yes | Owner user ID |
| `sort_order` | Integer | Yes | Manual sorting order |
| `created_at` | DateTime | Yes | Creation timestamp |
| `updated_at` | DateTime | Yes | Last update timestamp |
| `tags` | Array | No | Associated tags |

### Task Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `description` | String | null | Task description |
| `status` | Enum | "todo" | todo, in_progress, done, dropped |
| `priority` | Enum | "medium" | low, medium, high, urgent |
| `due_at` | DateTime | null | Due date |
| `earliest_start_at` | DateTime | null | Start date constraint |
| `completed_at` | DateTime | null | Completion timestamp |
| `archived` | Boolean | false | Archive status |

### Note Fields

| Field | Type | Description |
|-------|------|-------------|
| `body` | String | Markdown content |

### Template Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | String | Template description |
| `category` | String | Template category |
| `usage_count` | Integer | Times used |
| `target_node_id` | UUID | Where to instantiate |
| `create_container` | Boolean | Create container folder |

### Smart Folder Fields

| Field | Type | Description |
|-------|------|-------------|
| `rule_id` | UUID | Associated rule ID |
| `auto_refresh` | Boolean | Auto-refresh setting |
| `description` | String | Folder description |

## API Endpoints

### Authentication
- `POST /auth/login` - User login
- `POST /auth/signup` - User registration
- `GET /auth/user` - Get current user

### Nodes
- `GET /nodes` - List all nodes
- `GET /nodes/{id}` - Get single node
- `POST /nodes` - Create node
- `PATCH /nodes/{id}` - Update node
- `DELETE /nodes/{id}` - Delete node
- `GET /nodes/{id}/contents` - Smart folder contents

### Tags
- `GET /tags` - List all tags
- `POST /tags` - Create tag
- `GET /tags/search?q={query}` - Search tags
- `POST /nodes/{nodeId}/tags/{tagId}` - Attach tag
- `DELETE /nodes/{nodeId}/tags/{tagId}` - Detach tag
- `GET /nodes/{nodeId}/tags` - Get node tags

### Rules
- `GET /rules` - List rules
- `POST /rules` - Create rule
- `GET /rules/{id}` - Get rule
- `PATCH /rules/{id}` - Update rule
- `DELETE /rules/{id}` - Delete rule
- `POST /rules/{id}/execute` - Execute rule

### Templates
- `POST /templates/{id}/instantiate` - Use template

## Response Formats

### Success Response
```json
{
  "data": { ... },
  "message": "Success"
}
```

### Error Response
```json
{
  "error": "Error message",
  "code": 400
}
```

### List Response
```json
{
  "data": [ ... ],
  "count": 100,
  "page": 1,
  "total_pages": 5
}
```