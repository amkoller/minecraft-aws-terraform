# Minecraft Server on AWS

PaperMC Java server on a t4g.small (ARM, AL2023) with auto-stop, cost controls, and git-managed config. ~$2.45/mo fixed + ~$0.02/hr while running.

## Prerequisites

```bash
brew install terraform awscli jq
aws configure                          # region: us-east-2
ssh-keygen -t ed25519 -f ~/.ssh/minecraft -N ''
```

## First-time setup

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit: allowed_ssh_cidr (your IP/32), paper_version, ssh_public_key_path
```

```bash
cd terraform && terraform init && terraform apply   # ~3 min
cd ..
./mc ssh "cloud-init status --wait"                 # wait for provisioning
./mc deploy                                         # push initial config
./mc status                                         # confirm running + connect IP
```

## Daily ops

```
./mc start        # start instance → waits for port → prints Connect: <ip>:25565
./mc stop         # graceful RCON stop → halt EC2
./mc status       # instance state + current IP + port check
./mc deploy       # rsync config/ → inject rcon.password → systemctl restart minecraft
./mc ssh          # SSH into box (pass-through)
./mc logs         # tail journalctl (--no-follow for dump)
./mc backup-now   # run nightly backup script on demand
./mc restore <ts> # restore world from S3 timestamp
./mc rcon <cmd>   # arbitrary RCON command
```

Server auto-stops 60 minutes after the last player leaves (on-box cron every 5 min).
No Elastic IP — `./mc start` prints the new public IP each session.

## Config management

Edit files in `config/`, then `./mc deploy`. Never edit server files directly over SSH.

**Do not add `rcon.password` to `config/server.properties`** — it is stripped out of local config and injected on the box at deploy time from `/etc/minecraft/rcon.env`.

Deploy excludes `world*` directories — it will never overwrite your world.

## Backups

Nightly at 04:30 UTC → `s3://minecraft-backups-<account-id>/world/<timestamp>/`.
Transitions to Glacier IR at 30 days, expires at 180 days.

```bash
./mc backup-now                          # on-demand
aws s3 ls s3://$(terraform -chdir=terraform output -raw s3_backup_bucket)/world/
./mc restore 20240101T043000Z            # pick a timestamp from the listing
```

## Cost

| Usage | ~$/mo |
|---|---|
| Fixed (EBS + S3) | ~$2.45 |
| 1 hr/day play | ~$3.45 |
| 2 hr/day play | ~$3.90 |
| 4 hr/day play | ~$5.25 |
| 24/7 (no auto-stop) | ~$18.35 |

## Troubleshooting

| Problem | Check |
|---|---|
| Port 25565 not opening | `./mc ssh "cloud-init status"` — still provisioning? |
| World not loading | `./mc ssh "mount \| grep nvme1"` — EBS mounted? |
| Auto-stop not triggering | `./mc ssh "sudo tail -f /var/log/minecraft-autostop.log"` |
| Backup failed | `./mc ssh "sudo tail /var/log/minecraft-backup.log"` |
| RCON not working | `./mc ssh "sudo mcrcon -H 127.0.0.1 -P 25575 -p \$RCON_PASSWORD list"` |

## Security notes

- RCON binds to `127.0.0.1` only — no external access.
- Port 25575 has no security group rule (belt-and-suspenders).
- SSH locked to `allowed_ssh_cidr` in tfvars.
- RCON password is Terraform-managed, sensitive output, never committed.

## Destroying

To tear down (will prompt due to `prevent_destroy` on world EBS):

```bash
# First manually remove prevent_destroy from terraform/storage.tf if intentional
cd terraform && terraform destroy
```
