{
  "nodes": [
    {
      "id": "421824c2-59a2-441b-aacc-7dadf2ec153b",
      "name": "On clicking 'execute'",
      "type": "n8n-nodes-base.manualTrigger",
      "position": [
        900,
        1180
      ],
      "parameters": {},
      "typeVersion": 1
    },
    {
      "id": "c6024a57-1957-4714-84e3-8d326c83cd89",
      "name": "Sticky Note",
      "type": "n8n-nodes-base.stickyNote",
      "position": [
        420,
        1560
      ],
      "parameters": {
        "color": 6,
        "width": 1910.7813046051347,
        "height": 731.7039821513649,
        "content": "## Subworkflow"
      },
      "typeVersion": 1
    },
    {
      "id": "07691901-a8d2-4891-860b-1d672361021b",
      "name": "Execute Workflow Trigger",
      "type": "n8n-nodes-base.executeWorkflowTrigger",
      "position": [
        480,
        1940
      ],
      "parameters": {},
      "typeVersion": 1
    },
    {
      "id": "2b1dd138-7872-42ea-9882-8750ef4cf227",
      "name": "n8n",
      "type": "n8n-nodes-base.n8n",
      "position": [
        1300,
        1280
      ],
      "parameters": {
        "filters": {},
        "requestOptions": {}
      },
      "credentials": {
        "n8nApi": {
          "id": "t2YEgbUMXHjsykeF",
          "name": "admin"
        }
      },
      "typeVersion": 1
    },
    {
      "id": "96c0c6a7-2a11-441d-8177-e0a18030daf9",
      "name": "Return",
      "type": "n8n-nodes-base.set",
      "position": [
        2140,
        1760
      ],
      "parameters": {
        "options": {},
        "assignments": {
          "assignments": [
            {
              "id": "8d513345-6484-431f-afb7-7cf045c90f4f",
              "name": "Done",
              "type": "boolean",
              "value": true
            }
          ]
        }
      },
      "typeVersion": 3.3
    },
    {
      "id": "6715d1ff-a1f0-4e1a-b96e-f680d1495047",
      "name": "Get File",
      "type": "n8n-nodes-base.httpRequest",
      "position": [
        1100,
        1640
      ],
      "parameters": {
        "url": "={{ $json.download_url }}",
        "options": {}
      },
      "typeVersion": 4.2
    },
    {
      "id": "443b18e8-c05b-444f-b323-dea0b3041939",
      "name": "If file too large",
      "type": "n8n-nodes-base.if",
      "position": [
        860,
        1660
      ],
      "parameters": {
        "options": {},
        "conditions": {
          "options": {
            "leftValue": "",
            "caseSensitive": true,
            "typeValidation": "strict"
          },
          "combinator": "and",
          "conditions": [
            {
              "id": "45ce825e-9fa6-430c-8931-9aaf22c42585",
              "operator": {
                "type": "string",
                "operation": "empty",
                "singleValue": true
              },
              "leftValue": "={{ $json.content }}",
              "rightValue": ""
            },
            {
              "id": "9619a55f-7fb1-4f24-b1a7-7aeb82365806",
              "operator": {
                "type": "string",
                "operation": "notExists",
                "singleValue": true
              },
              "leftValue": "={{ $json.error }}",
              "rightValue": ""
            }
          ]
        }
      },
      "typeVersion": 2
    },
    {
      "id": "e460a2cd-f7af-4551-8ea2-84d9b9e5cb7f",
      "name": "Merge Items",
      "type": "n8n-nodes-base.merge",
      "position": [
        860,
        1920
      ],
      "parameters": {},
      "typeVersion": 2
    },
    {
      "id": "f795180a-66aa-4a86-acb0-96cf8c487db0",
      "name": "isDiffOrNew",
      "type": "n8n-nodes-base.code",
      "position": [
        1060,
        1920
      ],
      "parameters": {
        "jsCode": "const orderJsonKeys = (jsonObj) => {\n  const ordered = {};\n  Object.keys(jsonObj).sort().forEach(key => {\n    ordered[key] = jsonObj[key];\n  });\n  return ordered;\n}\n\n// Check if file returned with content\nif (Object.keys($input.all()[0].json).includes(\"content\")) {\n  // Decode base64 content and parse JSON\n  const origWorkflow = JSON.parse(Buffer.from($input.all()[0].json.content, 'base64').toString());\n  const n8nWorkflow = $input.all()[1].json;\n  \n  // Order JSON objects\n  const orderedOriginal = orderJsonKeys(origWorkflow);\n  const orderedActual = orderJsonKeys(n8nWorkflow);\n\n  // Determine difference\n  if (JSON.stringify(orderedOriginal) === JSON.stringify(orderedActual)) {\n    $input.all()[0].json.github_status = \"same\";\n  } else {\n    $input.all()[0].json.github_status = \"different\";\n    $input.all()[0].json.n8n_data_stringy = JSON.stringify(orderedActual, null, 2);\n  }\n  $input.all()[0].json.content_decoded = orderedOriginal;\n// No file returned / new workflow\n} else if (Object.keys($input.all()[0].json).includes(\"data\")) {\n  const origWorkflow = JSON.parse($input.all()[0].json.data);\n  const n8nWorkflow = $input.all()[1].json;\n  \n  // Order JSON objects\n  const orderedOriginal = orderJsonKeys(origWorkflow);\n  const orderedActual = orderJsonKeys(n8nWorkflow);\n\n  // Determine difference\n  if (JSON.stringify(orderedOriginal) === JSON.stringify(orderedActual)) {\n    $input.all()[0].json.github_status = \"same\";\n  } else {\n    $input.all()[0].json.github_status = \"different\";\n    $input.all()[0].json.n8n_data_stringy = JSON.stringify(orderedActual, null, 2);\n  }\n  $input.all()[0].json.content_decoded = orderedOriginal;\n\n} else {\n  // Order JSON object\n  const n8nWorkflow = $input.all()[1].json;\n  const orderedActual = orderJsonKeys(n8nWorkflow);\n  \n  // Proper formatting\n  $input.all()[0].json.github_status = \"new\";\n  $input.all()[0].json.n8n_data_stringy = JSON.stringify(orderedActual, null, 2);\n}\n\n// Return items\nreturn $input.all();\n"
      },
      "typeVersion": 1
    },
    {
      "id": "30e7d6fc-327e-4693-95ce-376a3b1f145c",
      "name": "Check Status",
      "type": "n8n-nodes-base.switch",
      "position": [
        1460,
        1920
      ],
      "parameters": {
        "rules": {
          "rules": [
            {
              "value2": "same"
            },
            {
              "output": 1,
              "value2": "different"
            },
            {
              "output": 2,
              "value2": "new"
            }
          ]
        },
        "value1": "={{$json.github_status}}",
        "dataType": "string"
      },
      "typeVersion": 1
    },
    {
      "id": "36f12309-c7fe-446f-9571-bd1005c18ed8",
      "name": "Same file - Do nothing",
      "type": "n8n-nodes-base.noOp",
      "position": [
        1680,
        1760
      ],
      "parameters": {},
      "typeVersion": 1
    },
    {
      "id": "45f0eaa7-259b-4908-b567-af2b3b5abb6d",
      "name": "File is different",
      "type": "n8n-nodes-base.noOp",
      "position": [
        1680,
        1920
      ],
      "parameters": {},
      "typeVersion": 1
    },
    {
      "id": "d16ec06b-7a3f-486e-8328-935ed3b4d565",
      "name": "File is new",
      "type": "n8n-nodes-base.noOp",
      "position": [
        1680,
        2120
      ],
      "parameters": {},
      "typeVersion": 1
    },
    {
      "id": "cdc7f306-b7d2-4de1-8e44-0bd8d49a679f",
      "name": "Create new file",
      "type": "n8n-nodes-base.github",
      "position": [
        1900,
        2120
      ],
      "parameters": {
        "owner": {
          "__rl": true,
          "mode": "",
          "value": "={{ $('Config').first().item.repo_owner }}"
        },
        "filePath": "={{ $('Config').first().item.repo_path }}{{ $json.subPath }}{{$('Execute Workflow Trigger').first().json.id}}.json",
        "resource": "file",
        "repository": {
          "__rl": true,
          "mode": "",
          "value": "={{ $('Config').first().item.repo_name }}"
        },
        "fileContent": "={{$('isDiffOrNew').item.json[\"n8n_data_stringy\"]}}",
        "commitMessage": "={{$('Execute Workflow Trigger').first().json.name}} ({{$json.github_status}})"
      },
      "typeVersion": 1
    },
    {
      "id": "9785333a-4a86-448d-afc2-58b0aa50ea96",
      "name": "Edit existing file",
      "type": "n8n-nodes-base.github",
      "position": [
        1900,
        1920
      ],
      "parameters": {
        "owner": {
          "__rl": true,
          "mode": "",
          "value": "={{ $('Config').first().item.repo_owner }}"
        },
        "filePath": "={{ $('Config').first().item.repo_path }}{{ $json.subPath }}{{$('Execute Workflow Trigger').first().json.id}}.json",
        "resource": "file",
        "operation": "edit",
        "repository": {
          "__rl": true,
          "mode": "",
          "value": "={{ $('Config').first().item.repo_name }}"
        },
        "fileContent": "={{$('isDiffOrNew').item.json[\"n8n_data_stringy\"]}}",
        "commitMessage": "={{$('Execute Workflow Trigger').first().json.name}} ({{$json.github_status}})"
      },
      "typeVersion": 1
    },
    {
      "id": "806db72c-c9f6-461d-be1a-1e6867a25382",
      "name": "Loop Over Items",
      "type": "n8n-nodes-base.splitInBatches",
      "position": [
        1500,
        1280
      ],
      "parameters": {
        "options": {}
      },
      "typeVersion": 3
    },
    {
      "id": "e5c433e4-bf56-4a0a-906c-7d74f6fe7287",
      "name": "Schedule Trigger",
      "type": "n8n-nodes-base.scheduleTrigger",
      "position": [
        900,
        1380
      ],
      "parameters": {
        "rule": {
          "interval": [
            {
              "triggerAtHour": 1,
              "triggerAtMinute": 33
            }
          ]
        }
      },
      "typeVersion": 1.2
    },
    {
      "id": "f6b566cb-0a15-4792-ba27-d6cd2a6c9453",
      "name": "Create sub path",
      "type": "n8n-nodes-base.set",
      "position": [
        1260,
        1920
      ],
      "parameters": {
        "options": {},
        "assignments": {
          "assignments": [
            {
              "id": "dae43d3b-56e5-4098-b602-862ebf5cd073",
              "name": "subPath",
              "type": "string",
              "value": "={{ $('Execute Workflow Trigger').first().json.createdAt.split('-')[0] }}/{{ $('Execute Workflow Trigger').first().json.createdAt.split('-')[1] }}/"
            }
          ]
        },
        "includeOtherFields": true
      },
      "typeVersion": 3.3
    },
    {
      "id": "9e2412f6-df25-4c12-8faf-0200558b537c",
      "name": "Sticky Note1",
      "type": "n8n-nodes-base.stickyNote",
      "position": [
        420,
        1100
      ],
      "parameters": {
        "color": 4,
        "width": 385,
        "height": 417,
        "content": "## Backup to GitHub \nThis workflow will backup all instance workflows to GitHub every 24 hours.\n\nThe files are saved into folders using `YYYY/MM/` for the directory path and `ID.json` for the filename.\n\nThe Repo Owner, Repo Name and Main folder are set using the **Variables** feature but can be replaced with the `Config` node in the subworkflow. \n\nThe workflow runs calls itself to help reduce memory usage, Once the workflow has completed it will send an optional notification to Slack.\n\n### Time to Run\nTested with 1423 workflows on `1.44.1` it took under 30 minutes for the first run and under 12 minutes once the initial run is complete."
      },
      "typeVersion": 1
    },
    {
      "id": "00fdb977-4f3e-49f6-81c3-bc7f9520914f",
      "name": "Sticky Note2",
      "type": "n8n-nodes-base.stickyNote",
      "position": [
        860,
        1100
      ],
      "parameters": {
        "color": 7,
        "width": 1272.6408145680155,
        "height": 416.1856906618075,
        "content": "## Main workflow loop"
      },
      "typeVersion": 1
    },
    {
      "id": "0c00a374-566a-49c7-80de-66a991c4bf69",
      "name": "Starting Message",
      "type": "n8n-nodes-base.slack",
      "position": [
        1140,
        1280
      ],
      "webhookId": "c02eb407-5547-4aa0-9ebf-46dab67b63b6",
      "parameters": {
        "text": "=:information_source:  Starting Workflow Backup [{{ $execution.id }}]",
        "select": "channel",
        "channelId": {
          "__rl": true,
          "mode": "name",
          "value": "#notifications"
        },
        "otherOptions": {
          "includeLinkToWorkflow": false
        }
      },
      "typeVersion": 2.2
    },
    {
      "id": "eb7d15be-7f5d-4e39-837b-06d740685af3",
      "name": "Execute Workflow",
      "type": "n8n-nodes-base.executeWorkflow",
      "onError": "continueErrorOutput",
      "position": [
        1720,
        1300
      ],
      "parameters": {
        "mode": "each",
        "options": {},
        "workflowId": "={{ $workflow.id }}"
      },
      "typeVersion": 1
    },
    {
      "id": "c831a0eb-95e1-46b3-bbf8-5d5bd928ca0a",
      "name": "Completed Notification",
      "type": "n8n-nodes-base.slack",
      "position": [
        1720,
        1120
      ],
      "webhookId": "a0c6e8c8-5d71-40fa-b02b-63a7ed5726c4",
      "parameters": {
        "text": "=✅ Backup has completed - {{ $('n8n').all().length }} workflows have been processed.",
        "select": "channel",
        "channelId": {
          "__rl": true,
          "mode": "name",
          "value": "#notifications"
        },
        "otherOptions": {}
      },
      "executeOnce": true,
      "typeVersion": 2.2
    },
    {
      "id": "00864cb8-c8e4-4324-be1b-7d093e1bc3bf",
      "name": "Failed Flows",
      "type": "n8n-nodes-base.slack",
      "position": [
        1920,
        1320
      ],
      "webhookId": "2a092edb-de12-490f-931b-34d70e7d7696",
      "parameters": {
        "text": "=:x: Failed to backup {{ $('Loop Over Items').item.json.id }}",
        "select": "channel",
        "channelId": {
          "__rl": true,
          "mode": "name",
          "value": "#notifications"
        },
        "otherOptions": {
          "includeLinkToWorkflow": false
        }
      },
      "typeVersion": 2.2
    },
    {
      "id": "e4d70af5-5c21-4340-8054-7ba0203f3ee1",
      "name": "Get file data",
      "type": "n8n-nodes-base.github",
      "position": [
        660,
        1660
      ],
      "parameters": {
        "owner": {
          "__rl": true,
          "mode": "",
          "value": "={{ $('Config').first().item.repo_owner }}"
        },
        "filePath": "={{ $('Config').first().item.repo_path }}{{ $('Execute Workflow Trigger').first().json.createdAt.split('-')[0] }}/{{ $('Execute Workflow Trigger').first().json.createdAt.split('-')[1] }}/{{$json.id}}.json",
        "resource": "file",
        "operation": "get",
        "repository": {
          "__rl": true,
          "mode": "",
          "value": "={{ $('Config').first().item.repo_name }}"
        },
        "asBinaryProperty": false,
        "additionalParameters": {}
      },
      "typeVersion": 1,
      "continueOnFail": true,
      "alwaysOutputData": true
    },
    {
      "id": "42ad4762-26fb-4686-9016-729e95c95324",
      "name": "Config",
      "type": "n8n-nodes-base.set",
      "position": [
        660,
        1940
      ],
      "parameters": {
        "options": {},
        "assignments": {
          "assignments": [
            {
              "id": "8f6d1741-772f-462a-811f-4c334185e4f0",
              "name": "repo_owner",
              "type": "string",
              "value": "={{ $vars.repo_owner }}"
            },
            {
              "id": "8cac215c-4fd7-422f-9fd2-6b2d1e5e0383",
              "name": "repo_name",
              "type": "string",
              "value": "={{ $vars.repo_name }}"
            },
            {
              "id": "eee305e9-4164-462a-86bd-80f0d58a31ae",
              "name": "repo_path",
              "type": "string",
              "value": "={{ $vars.repo_path }}"
            }
          ]
        },
        "includeOtherFields": true
      },
      "typeVersion": 3.4
    }
  ],
  "pinData": {},
  "connections": {
    "n8n": {
      "main": [
        [
          {
            "node": "Loop Over Items",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Config": {
      "main": [
        [
          {
            "node": "Get file data",
            "type": "main",
            "index": 0
          },
          {
            "node": "Merge Items",
            "type": "main",
            "index": 1
          }
        ]
      ]
    },
    "Get File": {
      "main": [
        [
          {
            "node": "Merge Items",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "File is new": {
      "main": [
        [
          {
            "node": "Create new file",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Merge Items": {
      "main": [
        [
          {
            "node": "isDiffOrNew",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "isDiffOrNew": {
      "main": [
        [
          {
            "node": "Create sub path",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Check Status": {
      "main": [
        [
          {
            "node": "Same file - Do nothing",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "File is different",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "File is new",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Failed Flows": {
      "main": [
        [
          {
            "node": "Loop Over Items",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Get file data": {
      "main": [
        [
          {
            "node": "If file too large",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Create new file": {
      "main": [
        [
          {
            "node": "Return",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Create sub path": {
      "main": [
        [
          {
            "node": "Check Status",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Loop Over Items": {
      "main": [
        [
          {
            "node": "Completed Notification",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "Execute Workflow",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Execute Workflow": {
      "main": [
        [
          {
            "node": "Loop Over Items",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "Failed Flows",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Schedule Trigger": {
      "main": [
        [
          {
            "node": "Starting Message",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Starting Message": {
      "main": [
        [
          {
            "node": "n8n",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "File is different": {
      "main": [
        [
          {
            "node": "Edit existing file",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "If file too large": {
      "main": [
        [
          {
            "node": "Get File",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "Merge Items",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Edit existing file": {
      "main": [
        [
          {
            "node": "Return",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "On clicking 'execute'": {
      "main": [
        [
          {
            "node": "Starting Message",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Same file - Do nothing": {
      "main": [
        [
          {
            "node": "Return",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Execute Workflow Trigger": {
      "main": [
        [
          {
            "node": "Config",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}