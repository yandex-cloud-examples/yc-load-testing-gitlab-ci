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
    - `compute.editor`
    - `vpc.user`
3. (Опционально) Для использования хранящихся в репозитории файлов с тестовыми данными, CI необходим бакет в Object Storage, куда эти файлы будут временно загружаться на время выполнения теста (**Сервис Load Testing не имеет доступа к вашим тестовым данным**). Сервисному аккаунту, в таком случае нужно одно из:
    - глобальная роль `storage.editor`
    - роль `editor` в ACL у конкретного бакета
4. [Создайте](https://yandex.cloud/ru/docs/iam/concepts/authorization/key) авторизованный ключ для сервисного аккаунта, сохраните `json` файл
  с ключом локально на диск.
5. [Добавьте](https://docs.gitlab.com/ee/ci/variables/#for-a-project) переменную `YC_LOADTESTING_CI_AUTHORIZED_KEY_JSON` в настройках **GitLab CI**. В качестве значения, вставьте содержимое скачанного `json` файла авторизованного ключа.

---

## 2. Настройте pipeline для нагрузочного тестирования в GitLab CI

### 2.1. Подключите GitLab CI шаблон нагрузочного тестирования в `gitlab-ci.yml`
1. Скачайте [шаблон .gitlab-loadtesting-ci.yml](templates/.gitlab-loadtesting-ci.yml), добавьте его в свой `git` репозиторий в папку `templates`
2. Подключите скачанный шаблон в ваш `gitlab-ci.yml`:
    ```yaml
    # .gitlab-ci.yml

    include:
    - templates/.gitlab-loadtesting-ci.yml
    ```
3. Скопируйте [дополнительные скрипты](automation/) в произвольное место в своем репозитории, укажите путь до выбранной папки в переменной `YC_LT_AUTOMATION_SCRIPTS_DIR` в `gitlab-ci.yml`:

    ```yaml
    # .gitlab-ci.yml

    variables:
      YC_LT_AUTOMATION_SCRIPTS_DIR: "./ci/loadtesting"
    ```

---

### 2.2. В `gitlab-ci.yml` определите переменные

Минимальные наборы необходимых переменных приведены ниже

**Без разворачивания агентов в `compute`**
```yaml
# .gitlab-ci.yml

.loadtesting-variables: &loadtesting-variables
  YC_LT_FOLDER_ID: '' # <-- id каталога
```

**С разворачиванием агентов в `compute`**
```yaml
# .gitlab-ci.yml

.loadtesting-variables: &loadtesting-variables
  YC_LT_FOLDER_ID: '' # id каталога

  YC_LT_AGENTS_CNT: 1 # количество агентов, разворачиваемых при запуске флоу
  YC_LT_AGENT_SA_ID: '' # id сервисного аккаунта
  YC_LT_AGENT_ZONE: 'ru-central1-b' # зона доступности, в которой будут разворачиваться ВМ
  YC_LT_AGENT_SUBNET_ID: '' # id подсети в указанной зоне доступности
  YC_LT_AGENT_SECURITY_GROUP_IDS: '' # id группы безопасности ВМ
```

Полный список переопределяемых параметров можно посмотреть [тут](automation/_variables.sh).

---

### 2.3. (Опционально) Добавьте в CI кубики с созданием и удалением агентов

```yaml
# .gitlab-ci.yml

stages:
  # ... стадии "до"
  - test-loadtesting
  - test-loadtesting-cleanup
  # ... стадии "после"

test-loadtesting-create-agents:
  extends: .yc-template-lt-job-create-compute-agent
  stage: test-loadtesting
  variables: *loadtesting-variables

test-loadtesting-delete-agents:
  extends: .yc-template-lt-job-delete-compute-agent
  stage: test-loadtesting-cleanup
  variables: *loadtesting-variables
```

_**Прим: дополнительная стадия нужна для того, чтобы гарантировать удаление агентов по завершению работы.**_

---

### 2.4. Добавьте файлы с описанием нагрузочных тестов в репозиторий

Для каждого теста, который планируется запускать, должна быть создана отдельная папка:
  - файл конфигурации сохраните под именем, соответствующим маске `test-config*.yaml`
  - файлы с тестовыми данными положите рядом - перед выполнением теста они будут временно загружены в Object Storage, а во время выполнения, агент их оттуда скачает

Имя теста, в таком случае, будет соответствовать имени папки, в которой находится файл конфигурации. 

_**Прим: О том, как переопределить имя создаваемого теста, а так же другие параметры запуска, можно прочитать [здесь](README-howto-add-test.md).**_

---

### 2.5. Добавьте в CI кубик с запуском тестов

```yaml
# .gitlab-ci.yml

stages:
  # ... стадии "до"
  - test-loadtesting
  # ... стадии "после"

test-loadtesting-run:
  extends: .yc-template-lt-job-run-test
  stage: test-loadtesting
  # при настроенных агентских кубиках, строчку ниже нужно раскомментировать
  # needs: [test-loadtesting-create-agents] 
  variables:
    <<: *loadtesting-variables
    YC_LT_DATA_BUCKET: ''
    YC_LT_TESTS: |-
      sample-tests/smoke
      sample-tests/mixed-synthetic-payload
      sample-tests/mixed-irl-payload
      sample-tests/mixed-irl-payload-multi
      sample-tests/root-const
      sample-tests/root-imbalance
```

Переменные:
- `YC_LT_DATA_BUCKET` - имя Object Storage бакета. Бакет должен находиться в том же каталоге облака,
  куда загружаются тесты.

  - **WARNING: У сервисного аккаунта, с которым запускается агент, должны быть права на чтение файлов из этого бакета.**

  - **WARNING2: У сервисного аккаунта, ключ которого используется в GitLab CI, должны быть права на загрузку файлов в этот бакет.**
- `YC_LT_TESTS` - список директорий с тестами, которые необходимо запустить в рамках этого кубика.

#### Если используются свои агенты

Дополнительно, если за создание/удаление агентов отвечают НЕ предлагаемые выше кубики, нужно определить
переменную `YC_LT_TEST_AGENT_FILTER` со значенем, cоответствующим по формату полю `filter` в `loadtesting.AgentService/List` API. 

_**Прим: Протестировать валидность фильтра можно через CLI: `yc loadtesting agent list --filter "MY_FILTER_STRING"`.**_

Например:

```yaml
# .gitlab-ci.yaml 

# test-loadtesting-run:
#   variables:

# агенты с именем, содержащим `my-string`
YC_LT_TEST_AGENT_FILTER: 'name contains "my-string"'

# агенты с метками `k: v` и `k2: v2`
YC_LT_TEST_AGENT_FILTER: `labels.k = "v" and labels.k2 = "v2"`
```

---

### 2.6 (Опционально) Настройте правила запуска нагрузочных тестов

- По коммитам в основноую ветку
- По обновлению в Pull Request

---

### 2.7. (Опционально) Настройте графики регрессий

Чтобы следить за эволюцией производительности сервиса/теста во времени, вы можете создать и настроить [графики регрессий](https://yandex.cloud/ru/docs/load-testing/concepts/load-test-regressions).