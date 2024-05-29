## 0. Ознакомление

Ознакомьтесь с сервисом: https://yandex.cloud/ru/docs/load-testing/

---

### 0.1. Определитесь, с каких агентов будет генерироваться нагрузка

Нагрузка в **YC Load Testing** генерируется нодами, называемыми агентами нагрузочного тестирования. На данный момент сервис предоставляет две опции по созданию таких агентов тестирования:
- Агент в **Yandex Compute Cloud** ([подробнее...](https://yandex.cloud/ru/docs/load-testing/operations/create-agent))
- Внешний агент ([подробнее...](https://yandex.cloud/ru/docs/load-testing/tutorials/loadtesting-external-agent))

_Управление внешними агентами нагрузочного тестирования осуществляется пользователем._

---

### 0.2. Подготовьте файлы конфигурации для нагрузочных тестов

Процесс подготовки конфигурационных файлов и файлов с тестовыми данными включает в себя непостредственно написание этих файлов и отладку. Все эти подготовительные работы рекомендуется проводить через UI в консоли управления.

О том, как начать пользоваться сервисом и создать свои первые тесты, можно узнать в разделе "Практические руководства" в [документации сервиса](https://yandex.cloud/ru/docs/load-testing/).

---

## 1. Настройте доступ из GitLab CI в Yandex Cloud

1. [Создайте](https://yandex.cloud/ru/docs/iam/quickstart-sa) сервисный аккаунт, от имени которого будут запускаться нагрузочные тесты
2. Выдайте сервисному аккаунту необходимые роли:
    - `loadtesting.loadTester`
3. (Опционально) Если вы планируете разворачивать `compute` агента нагрузочного тестирования в рамках CI, выдайте так же следующие роли:
    - `iam.serviceAccounts.user`
    - `compute.editor`
    - `vpc.user`
    - `vpc.publicAdmin` (опционально, если агент будет разворачиваться в публичной сети)
3. (Опционально) Для использования файлов из репозитория в качестве тестовых данных, необходимо использовать промежуточное хранилище в виде бакета в Object Storage (во время выполнения теста, CI будет туда файлы, а агент скачивать):
    - создайте бакет в Object Storage
    - выдайте права на запись одним из следующих способов:
        - `storage.editor` (глобальная роль в каталоге)
        - `editor` (ACL в бакете)
4. [Создайте](https://yandex.cloud/ru/docs/iam/concepts/authorization/key) авторизованный ключ для сервисного аккаунта, сохраните `json` файл с ключом локально на диск.
5. [Добавьте](https://docs.gitlab.com/ee/ci/variables/#for-a-project) переменную `YC_LOADTESTING_CI_AUTHORIZED_KEY_JSON` в настройках **GitLab CI**. В качестве значения, вставьте содержимое скачанного `json` файла авторизованного ключа.

---

## 2. Добавьте файлы с конфигурациями нагрузочных тестов в репозиторий

Для каждого теста, который планируется запускать, должна быть создана отдельная папка:
  - файл конфигурации сохраните под именем, соответствующим маске `test-config*.yaml`.
  - файлы с тестовыми данными положите рядом - перед выполнением теста они будут временно загружены в Object Storage, а во время выполнения, агент их оттуда скачает.

Имя теста, в таком случае, будет соответствовать имени папки, в которой находится файл конфигурации. 

_**Прим: О том, как переопределить имя создаваемого теста, а так же другие параметры запуска, можно прочитать [здесь](README-howto-add-test.md).**_

_**Примеры можно посмотреть в папке [sample-tests](sample-tests/).**_

---

## 3. Настройте pipeline для нагрузочного тестирования в GitLab CI

### 3.1. Создайте родительский `job` для с настройкой необходимого для запуска тестов окружения

Для создания тестов и управления агентами в рамках CI, необходимо следующее:
  - установлены утилиты командной строки: `curl`, `jq`.
  - установлена и настроена утилита командной строки [YC CLI](https://yandex.cloud/ru/docs/cli/).

В данной инструкции мы добавим `job` `.test-loadtesting-template`, и все последующие шаги будем наследовать от нее с помощью `extends: .test-loadtesting-template`.

```yaml
# .gitlab-ci.yml

.test-loadtesting-template:
  variables:
    # авторизованный ключ сервисного аккаунта
    YC_LT_AUTHORIZED_KEY_JSON: ${YC_LOADTESTING_CI_AUTHORIZED_KEY_JSON} 
    # id каталога для сервиса Load Testing
    YC_LT_FOLDER_ID: '%%%_CHANGE_ME_%%%'
  before_script: 
    - if [[ -z $YC_LT_AUTHORIZED_KEY_JSON ]]; then exit 1; fi
    - if [[ -z $YC_LT_FOLDER_ID ]]; then exit 1; fi

    # ----------------------------- install utilities ---------------------------- #
    - DEBIAN_FRONTEND=noninteractive apt update
    - DEBIAN_FRONTEND=noninteractive apt install -y curl jq

    - curl -f -s -LO https://storage.yandexcloud.net/yandexcloud-yc/install.sh
    - bash install.sh -i /usr/local/yandex-cloud -n
    - ln -sf /usr/local/yandex-cloud/bin/yc /usr/local/bin/yc

    # ----------------------------- configure yc cli ----------------------------- #
    - echo "${YC_LT_AUTHORIZED_KEY_JSON}" > key.json
    - yc config profile create sa-profile
    - yc config set service-account-key key.json
    - yc config set format json
    - yc config set folder-id ${YC_LT_FOLDER_ID}
```

_**Прим: Для того, чтобы избежать необходимости настройки окружения при каждом запуске, вы также можете выполнить эту настройку непосредственно на GitLab Runner.**_

---

### 3.2. (Опционально) Добавьте шаги для управления временными `compute` агентами

Чтобы избежать простоя агентских ВМ, добавьте шаги по их созданию и удалению в рамках `pipeline`.

```yaml
# .gitlab-ci.yml

stages:
  # ... стадии "до"
  - test-loadtesting
  - test-loadtesting-cleanup
  # ... стадии "после"

test-loadtesting-create-agents:
  extends: .test-loadtesting-template-job
  stage: test-loadtesting
  script:
    - set -e
    - automation/agent.sh create --count 2 \
        --description "CI agent" \
        --labels "pipeline=${CI_PIPELINE_IID}" \
        --service-account-id "###SECRET###" \
        --zone "###SECRET###" \
        --network-interface "subnet-id=###SECRET###,security-group-ids=###SECRET###" \
        --cores 2 \
        --memory 2G

test-loadtesting-delete-agents:
  extends: .test-loadtesting-template-job
  stage: test-loadtesting-cleanup
  when: always
  interruptible: false
  script:
    - set -e
    - automation/agent.sh delete \
        --labels "pipeline=${CI_PIPELINE_IID}"
```

  1. `test-loadtesting-create-agents` - создание агентов; параметры, передаваемые в `automation/agent.sh create` необходимо заменить на свои значения
      - `stage: test-loadtesting`, в этой же стадии будут запускаться тесты
      - `automation/agent.sh create` совместим `yc loadtesting agent create`, но добавлен параметр `--count` для удобного создания нескольких агентов одновременно.

  2. `test-loadtesting-delete-agents` - удаление агентов
      - `stage: test-loadtesting-cleanup`, стадия должна запускаться даже если во время создания агентов или запуска произошла ошибка
      - `automation/agent.sh delete` - дополнительный скрипт, который удаляет с метками, передаваемыми в `--labels "label1=valu1,label2=value2"`

---

### 3.3. Определите шаг с запуска нагрузочных тестов

```yaml
# .gitlab-ci.yml

stages:
  # ... стадии "до"
  - test-loadtesting
  # ... стадии "после"

test-loadtesting-run:
  extends: .test-loadtesting-template-job
  stage: test-loadtesting

  # ресурсная группа, предотвращает параллельное выполнение 
  # нагрузочных тестов из нескольких pipeline
  resource_group: loadtesting 

  # шаг создания compute агентов
  needs: [test-loadtesting-create-agents] 

  script:
    - set -e

    # automation/test.sh умеет заменять ${YC_LT_TARGET} в файлах
    # c тестовыми конфигурациями
    #
    - export YC_LT_TARGET="###SECRET###"
  
    # имя Object Storage бакета, используемого для передачи на агент
    # хранящихся в репозитории файлов с тестовыми данными
    #
    - export YC_LT_DATA_BUCKET="###SECRET###"

    # определяем критерий выбора агентов, на которых будут запускаться тесты
    #
    - export YC_LT_TEST_AGENT_FILTER="labels.pipeline = '${CI_PIPELINE_IID}'"

    # добавляем ссылку на pipeline в описание создаваемых тестов
    #
    - export YC_LT_TEST_EXTRA_DESCRIPTION="GitLab CI url - ${CI_PIPELINE_URL}"

    # передаем список тестов для запуска
    #
    - automation/test.sh \
        sample-tests/smoke \
        sample-tests/mixed-synthetic-payload \
        sample-tests/mixed-irl-payload \
        sample-tests/mixed-irl-payload-multi \
        sample-tests/root-const \
        sample-tests/root-imbalance

```

`automation/test.sh` принимает набор директорий, в которых находятся конфигурации тестов. Для каждого теста-директории выполняются следующии шаги:
- Подготовка:
  1. Помечает все неконфигурационные файлы в директории как файлы с тестовыми данными.
  2. Выгружает файлы с тестовыми данными в бакет `YC_LT_DATA_BUCKET`.
  3. Определяет парамеры создания тестас помощью `meta.json`. Параметры включают в себя: описание теста; метки теста; обязательные метки агентов; дополнительные файлы с тестовыми данными; количество агентов для параллельного запуска.
- Запуск:
  1. Создает тест.
  2. Дожидается завершения его выполнения.
- Проверка с помощью `automation/_test_check.sh`:
  1. Выполняет скрипт проверки свойств теста `test_dir/check_summary.sh`.
  2. Выполняет скрипт проверки результатов теста `test_dir/check_report.sh`.

Дополнительно, `automation/test.sh` учитывает следующие переменные окружения:
- `YC_LT_DATA_BUCKET` - имя Object Storage бакета, используемого для передачи на агент хранящихся в репозитории файлов с тестовыми данными.
    - **WARNING: У сервисного аккаунта, с которым запускается агент, должны быть права на чтение файлов из этого бакета.**
    - **WARNING2: У сервисного аккаунта, ключ которого используется в GitLab CI, должны быть права на загрузку файлов в этот бакет.**
- `YC_LT_TEST_AGENT_FILTER` - дополнительный фильтр для выбора агентов
    - _**Прим: Протестировать валидность фильтра можно через CLI:**_  
      `yc loadtesting agent list --filter "MY_FILTER_STRING"`.
- `YC_LT_SKIP_TEST_CHECK` - флаг, отключащий стадию проверок (любое отличное от `0` значение для отключения).

---

### 3.4. (Дополнительно) Настройте правила запуска нагрузочных тестов

- По коммитам в основноую ветку
- По обновлению в Pull Request

---

### 3.5. (Дополнтительно) Настройте графики регрессий

Чтобы следить за эволюцией производительности сервиса/теста во времени, вы можете создать и настроить [графики регрессий](https://yandex.cloud/ru/docs/load-testing/concepts/load-test-regressions).