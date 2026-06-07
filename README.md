# ymm — Serverless Music Player on AWS

A browser-based music player that runs entirely on a static, serverless AWS
stack. Upload mp3 files to S3, manage the playlist with a single static JSON
file, and play them with continuous playback — all behind HTTP Basic Auth.

## Architecture

```
  Browser
    │  HTTPS + Basic Auth
    ▼
  CloudFront ──── CloudFront Function (viewer-request)  ← Basic Auth gate
    │             (no Lambda, runs at the edge)
    │  Origin Access Control (SigV4)
    ▼
  S3 bucket (private)
    ├── index.html / app.js / style.css   ← the player UI
    ├── playlist.json                      ← the playlist (static file)
    └── music/*.mp3                         ← your audio
```

- **Fully serverless & static** — no servers, no backend, no databases. Just
  S3 + CloudFront + a CloudFront Function.
- **Basic Auth** is enforced at the CloudFront edge by a CloudFront Function,
  so the bucket and content are never publicly reachable.
- **The S3 bucket is private**; only CloudFront can read it (Origin Access
  Control).
- **Playlist management** is just uploading `playlist.json`.
- **Continuous playback**, shuffle, repeat, seek, volume, and keyboard
  shortcuts are built in.

## Project layout

```
.
├── site/                 # static player (uploaded to S3 by Terraform)
│   ├── index.html
│   ├── app.js
│   ├── style.css
│   └── playlist.json
├── music/                # your mp3s (git-ignored; uploaded by deploy.sh)
├── terraform/            # IaC: S3 + CloudFront + Basic Auth function
└── scripts/
    ├── gen-playlist.sh   # build playlist.json from ./music
    ├── serve.sh          # run the player locally (no AWS) — see "Run locally"
    ├── serve.py          # tiny local HTTP server with /music routing + Range
    └── deploy.sh         # sync music + playlist to S3, invalidate cache
```

## Run locally

Want to try the player without touching AWS? Drop a few `.mp3` files into
`./music/` and run:

```bash
./scripts/serve.sh          # http://127.0.0.1:8000
./scripts/serve.sh 9000     # …or pick a port
```

This regenerates `playlist.json` and serves `./site` over HTTP, transparently
mapping `/music/*` to your local `./music` directory — exactly the layout the
player sees on CloudFront. Open the printed URL in your browser; continuous
playback, shuffle, repeat, volume and **seeking** (HTTP Range requests) all
work locally. Press `Ctrl+C` to stop.

> The player loads `playlist.json` with `fetch()`, so opening
> `site/index.html` directly via `file://` will not work — use this server.
> Requires `python3` (already present on macOS and most Linux distros); no
> other dependencies.

## Prerequisites

- An AWS account and credentials configured (`aws configure` / `AWS_PROFILE`).
- [Terraform](https://www.terraform.io/) >= 1.3
- The AWS CLI (`aws`) for uploading music with `deploy.sh`.

## Deploy

### 1. Provision the infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set a globally-unique project_name (bucket name)

# set the Basic Auth password (kept out of state files / VCS)
export TF_VAR_basic_auth_password='your-strong-password'

terraform init
terraform apply
```

Terraform creates the S3 bucket, uploads the static site, sets up CloudFront
with Origin Access Control, and publishes the Basic Auth CloudFront Function.

> Note: the bucket name must be globally unique. Change `project_name` if
> `terraform apply` reports the bucket already exists.

### 2. Add music and deploy it

Drop `.mp3` files into `./music/`, then:

```bash
./scripts/deploy.sh
```

This regenerates `playlist.json`, uploads the music and playlist to S3, and
invalidates the CloudFront cache. For nicely-labelled tracks, name your files
`Artist - Title.mp3`.

### 3. Open the player

```bash
terraform -chdir=terraform output -raw cloudfront_url
```

Open that URL, log in with your Basic Auth credentials, and play.

## Managing the playlist

The playlist is the single static file `playlist.json`:

```json
{
  "tracks": [
    { "title": "Song", "artist": "Someone", "src": "music/song.mp3" }
  ]
}
```

Two ways to manage it:

- **Automatic** — put mp3s in `./music/` and run `./scripts/deploy.sh`; the
  playlist is generated from the file names.
- **Manual** — edit `site/playlist.json` (reorder, rename, group), then upload
  just that file:

  ```bash
  aws s3 cp site/playlist.json "s3://<bucket>/playlist.json" \
    --content-type application/json --cache-control no-cache
  aws cloudfront create-invalidation --distribution-id <id> --paths /playlist.json
  ```

## Updating the player UI

If you change `index.html` / `app.js` / `style.css`, re-upload them:

```bash
./scripts/deploy.sh --all      # uploads site + music + playlist, invalidates /*
```

(Or just run `terraform apply` again — Terraform tracks the site assets too.)

## Changing the password

```bash
export TF_VAR_basic_auth_password='new-password'
terraform -chdir=terraform apply
```

The CloudFront Function is re-published with the new credential.

## Tear down

```bash
cd terraform
terraform destroy
```

> If S3 reports the bucket is not empty (because `deploy.sh` added music after
> `apply`), empty it first: `aws s3 rm "s3://<bucket>" --recursive`.

## Cost

For personal use this is effectively pennies: S3 storage for your mp3s, a tiny
amount of CloudFront transfer, and CloudFront Function invocations (the first
2M/month are free). No always-on compute.
```
