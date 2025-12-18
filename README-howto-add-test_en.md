# How to define tests to run in CI

Make sure each test configuration resides in a dedicated folder. The configuration file name must be in `test-config*.yaml` format.

---

### TL;DR

You can view examples of defined tests [here](sample-tests/README.md).

You can add the following files to the configuration folder:
* `meta.json`: To define test properties. All fields in this file are optional.

    ```yaml
    # Test name
    name: str
    # Test description
    description: str
    # Test labels
    labels: {"test-label": "value"}
    # Labels of agents to run tests on
    agent_labels: {"agent-label": "value"}
    # Number of agents per configuration file
    multi: 1 
    # Array of external file sources (outside this repository)
    external_data: [{"name": "", "s3bucket": "", "s3file": ""}]
    ```

* `check_summary.sh`: To provide `yc loadtesting test get $test_id` validation.
* `check_report.sh`: To provide `yc loadtesting test get-report-tables $test_id` validation.

---

### Configuring a test in `meta.json`

You can define certain test settings in `meta.json`.

* Test name:

    ```json
    {
        "name": "smoke"
    }
    ```

* Test description:

    ```json
    {
        "description": "If this test fails... ALARM!!!!!!!!!"
    }
    ```

* Test labels:

    ```json
    {
        "labels": {
            "k1": "v1",
            "k2": "v2"
        }
    }
    ```

* Agent requirements defined by agent labels:

    ```json
    {
        "agent_labels": {
            "net": "1gb",
            "disk": "ssd"
        }
    }
    ```

---

### Feeding test data to the agent

#### From a repository

Since agents typically cannot download files directly from a repository, you need to employ an intermediate storage accessible to both the agent and CI. You may use Object Storage for this purpose.

When specifying the bucket name via the `YC_LT_DATA_BUCKET` environment variable:
1. All files from the test folder are uploaded to the `YC_LT_DATA_BUCKET` bucket, excluding service files, such as `meta.json`, `config*.yaml`, etc.
1. Information about the required files is included in the test creation request for the agent.
1. After the test is completed, the files uploaded at step 1 are deleted from the bucket.

_**WARNING: Make sure the service account used to run the agent have permissions to read files in this bucket.**_  
_**WARNING2: Make sure the service account used to create tests has permissions to upload files to this bucket.**_

#### From an Object Storage bucket:

This method works well if your test data originates from Object Storage.

In `meta.json`, you can define the `external_data` section, listing structures that specify the bucket name, the file name in the bucket, and the name the agent will give to the file when downloading it.

_**WARNING: Make sure the service account used to run the agent have permissions to read files in the specified buckets.**_

Example:

```json
{
    "external_data": [
        {
            "s3bucket": "loadtesting-data",
            "s3file": "folder/user-data.json",
            "name": "data.json"
        },
        {
            "s3bucket": "loadtesting-data",
            "s3file": "folder/payload.uri",
            "name": "payload.uri"
        }
    ]
}
```

---

### Running a test on multiple agents simultaneously (multitest)

In `meta.json`, you can set the `multi` parameter to the number of agents you want to use for running your test concurrently.

```json
{
    "multi": 3
}
```

_**WARNING: Testing will not start until all agents are connected to the service.**_

---

### Validation of test results in CI

By default, the system run includes some checks. For each test, you can override the default checks by adding the `check_summary.sh` and `check_result.sh` scripts to the test folder.

After the test is complete, these scripts will be called as shown below:

```sh
# download results

yc --format json loadtesting test get "$test_id" > summary.json
yc --format json loadtesting test get-report-table "$test_id" > report.json

# check

bash $test_dir/check_summary.sh summary.json
rc1=$?

bash $test_dir/check_report.sh report.json
rc2=$?

((rc1 == 0 && rc2 == 0))
```

A test is considered failed if one of the scripts returns the `exit_code != 0` error.

_**Note: To fully disable the checks, set `YC_LT_SKIP_TEST_CHECK=1`.**_
