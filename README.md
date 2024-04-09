# Настройка запуска нагрузочных тестов из GitLab CI

## 0. Ознакомление

Ознакомьтесь с сервисом: https://yandex.cloud/ru/docs/load-testing/

### 0.1. Определитесь, с каких агентов будет генерироваться нагрузка

Нагрузка в **YC Load Testing** генерируется нодами, называемыми агентами нагрузочного тестирования. На данный момент сервис предоставляет две опции по созданию таких агентов тестирования:
- Агент в **Yandex Compute Cloud** ([подробнее...](https://yandex.cloud/ru/docs/load-testing/operations/create-agent))
- Внешний агент ([подробнее...](https://yandex.cloud/ru/docs/load-testing/tutorials/loadtesting-external-agent))

_Управление внешними агентами нагрузочного тестирования осуществляется пользователем._

### 0.2. Подготовьте файлы конфигурации для нагрузочных тестовё

Процесс подготовки конфигурационных файлов и файлов с тестовыми данными включает в себя непостредственно написание этих файлов и отладку. Все эти подготовительные работы рекомендуется проводить через UI в консоли управления.

О том, как начать пользоваться сервисом и создать свои первые тесты, можно почитать в разделе "Практические руководства" в [документации сервиса](https://yandex.cloud/ru/docs/load-testing/).


## 1. Настройте доступ из GitLab CI в Yandex Cloud

1. [Создайте](https://yandex.cloud/ru/docs/iam/quickstart-sa) сервисный аккаунт, от имени которого будут запускаться нагрузочные тесты
2. Выдайте сервисному аккаунту необходимые роли:
    - `loadtesting.loadTester`
3. (Опционально) Если вы планируете разворачивать `compute` агента нагрузочного тестирования в рамках CI, выдайте так же следующие роли:
    - `compute.editor`
    - `vpc.user`
4. [Создайте](https://yandex.cloud/ru/docs/iam/concepts/authorization/key) авторизованный ключ для сервисного аккаунта, сохраните `json` файл
  с ключом локально на диск.
5. [Добавьте](https://docs.gitlab.com/ee/ci/variables/#for-a-project) переменную `YC_LOADTESTING_CI_AUTHORIZED_KEY_JSON` в настройках **GitLab CI**. В качестве значения, вставьте содержимое скачанного `json` файла авторизованного ключа

## 2. Настройте pipeline для нагрузочного тестирования в GitLab CI

### 2.1. Подключите GitLab CI шаблон нагрузочного тестирования в `gitlab-ci.yml`
1. Скачайте [шаблон](templates/.gitlab-loadtesting-ci.yml), добавьте его в свой `git` репозиторий в папку `${project-root}/templates`
2. Подключите скачанный шаблон в ваш `gitlab-ci.yml`:
    ```yaml
    include:
    - templates/.gitlab-loadtesting-ci.yml
    ```

### 2.3. В `gitlab-ci.yml` определите необходимые для нагрузочного тестирования переменные

**Минимальный набор переменных для запуска тестов, без разворачивания агента:**
```yaml
.lt_variables: &lt_variables
    lt_folder_id: ''
    lt_agent_name: ''
```

**Минимальный набор переменных для запуска тестов с предварительном разворачивании агента в `compute`:**
```yaml
.lt_variables: &lt_variables
    lt_folder_id: '' 
    lt_agent_service_account_id: '' 
    lt_agent_zone: ''
    lt_agent_subnet_id: ''
    lt_agent_security_group_id: ''
```

Полный список используемых в шаблоне переменных можно посмотреть в самом [шаблоне](templates/.gitlab-loadtesting-ci.yml).

### 2.3. (Опционально) Добавьте кубики с созданием и удалением агентов нагрузочного тестирования

```yaml
load-test-prepare-infra:
  extends: .yc-template-lt-job-setup-compute-agent
  stage: loadtesting
  variables:
    <<: *lt_variables

load-test-destroy-infra:
  extends: .yc-template-lt-job-delete-compute-agent
  stage: loadtesting-cleanup
  variables:
    <<: *lt_variables
```

**Прим: чтобы этап удаления не делать зависимым от каждого из тестов, запуск тестов и удаление агента лучше разносить по разным `stage`. В примере выше предполагается, следующая разбивка:**
1. `loadtesting` stage
    - создание агента
    - запуск первого теста
    - запуск второго теста
    - ...
2. `loadtesting-cleanup` stage
    - удаление агента

### 2.4. Добавьте подготовленные файлы конфигураций нагрузочных тестов в репозиторий

### 2.5. Добавьте кубики с запуском нагрузочных тестов

```yaml
load-test-job-const:
  extends: .yc-template-lt-job-run-test
  stage: loadtesting
  needs: [load-test-prepare-infra] # remove if needed
  variables:
    <<: *lt_variables
    lt_test_config_path: ${CI_PROJECT_DIR}/path/to/const-load-config.yaml # <-- path to your test configuration here
    lt_test_name: test-const-load # <-- test name

load-test-job-imbalance:
  extends: .yc-template-lt-job-run-test
  stage: loadtesting
  needs: [load-test-prepare-infra] # remove if needed
  variables:
    <<: *lt_variables
    lt_test_config_path: ${CI_PROJECT_DIR}/path/to/imbalance-load-config.yaml # <-- path to your test configuration here
    lt_test_name: test-imbalance-point # <-- test name
```

### 2.6 (Опционально) Добавьте кубики с проверками результатов созданных нагрузочных тестов

```yaml
check-load-test-job-const:
  extends: .yc-template-lt-job-check-test
  stage: loadtesting
  needs: [load-test-job-const]
  dependencies: [load-test-job-const]
  script:
    - function check_info { jq -r "$1" < ./lt_test_info.json; }
    - function check_report { jq -r "$1" < ./lt_test_report.json; }

    - set -ex
    - '[[ true == $(check_info ".summary.status == \"DONE\"") ]]'
    - '[[ true == $(check_report ".overall.quantiles.q50 < 50") ]]'
    - '[[ true == $(check_report ".overall.quantiles.q90 < 100") ]]'

check-load-test-job-imbalance:
  extends: .yc-template-lt-job-check-test
  stage: loadtesting
  needs: [load-test-job-imbalance]
  dependencies: [load-test-job-imbalance]
  script:
    - function check_info { jq -r "$1" < ./lt_test_info.json; }
    - function check_report { jq -r "$1" < ./lt_test_report.json; }

    - set -ex
    - '[[ true == $(check_info ".summary.status == \"AUTOSTOPPED\"") ]]'
    - '[[ true == $(check_info ".summary.imbalance_point.rps > 1000") ]]'
```

### 2.7 (Опционально) Настройте правила запуска нагрузочных тестов

- По коммитам в основноую ветку
- По обновлению в Pull Request

### 2.8. (Опционально) Настройте графики регрессий

Чтобы следить за эволюцией производительности сервиса/теста во времени, вы можете создать и настроить [графики регрессий](https://yandex.cloud/ru/docs/load-testing/concepts/load-test-regressions).
