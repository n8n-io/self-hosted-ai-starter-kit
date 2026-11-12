# n8n variants

## databases

| variant    | database |
|------------|----------|
| dev        | sqlite   |
| build      | postgres |
| community  | postgres |
| enterprise | postgres |

## capabilities

| variant    | code     | webhooks | executions | service | license  |
|------------|----------|----------|------------|---------|----------|
| dev        | isolated |          |            |         |          |
| build      | isolated | scaled   |            |         |          |
| community  | isolated | scaled   | scaled     |         |          |
| enterprise | isolated | scaled   | scaled     | scaled  | required |

## features

| capability        | feature                                                                                                              |
|-------------------|----------------------------------------------------------------------------------------------------------------------|
| code isolated     | [task runner](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-task-runners)                                 |
| webhooks scaled   | [webhook processors](https://docs.n8n.io/deploy/host-n8n/configure-n8n/scaling/enable-queue-mode#webhook-processors) |
| executions scaled | [queue mode](https://docs.n8n.io/deploy/host-n8n/configure-n8n/scaling/enable-queue-mode)                            |
| service scaled    | [multi main](https://docs.n8n.io/deploy/host-n8n/configure-n8n/scaling/enable-queue-mode#multi-main-setup)           |