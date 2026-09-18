# API examples

Base URL:

```text
http://127.0.0.1:15721
```

Every protected browser request needs the configured Origin and `X-WinUtil-Token` header.

## Health

```http
GET /api/v1/health
```

No token is required.

## List tweaks

```javascript
const tweaks = await fetch('http://127.0.0.1:15721/api/v1/tweaks', {
  headers: { 'X-WinUtil-Token': token }
}).then(r => r.json());
```

## Scan

```javascript
const result = await fetch('http://127.0.0.1:15721/api/v1/scan', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-WinUtil-Token': token
  },
  body: JSON.stringify({ tweakIds: ['Privacy.Telemetry'] })
}).then(r => r.json());
```

## Preview

```javascript
await fetch('http://127.0.0.1:15721/api/v1/preview', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-WinUtil-Token': token
  },
  body: JSON.stringify({
    tweakIds: ['Privacy.Telemetry', 'Privacy.BingSearch'],
    profile: 'safe'
  })
});
```

## Apply

```javascript
const job = await fetch('http://127.0.0.1:15721/api/v1/apply', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-WinUtil-Token': token
  },
  body: JSON.stringify({
    tweakIds: ['Privacy.Telemetry', 'Privacy.BingSearch'],
    profile: 'safe',
    allowWithoutRestorePoint: false
  })
}).then(r => r.json());
```

Poll the job:

```javascript
const status = await fetch(`http://127.0.0.1:15721/api/v1/jobs/${job.id}`, {
  headers: { 'X-WinUtil-Token': token }
}).then(r => r.json());
```

## Rollback

```javascript
await fetch(`http://127.0.0.1:15721/api/v1/rollback/${transactionId}`, {
  method: 'POST',
  headers: { 'X-WinUtil-Token': token }
});
```
