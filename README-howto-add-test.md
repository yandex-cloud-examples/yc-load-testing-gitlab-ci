# Как описывать тесты, которые необходимо запускать в CI

Конфигурация каждого теста должна лежать в отдельной папке. Имя конфигурационного файла должно соответствовать маске `test-config*.yaml`.

---

### TL;DR

_**Примеры описанных тестов можно посмотреть [тут](sample-tests/README.md).**_

В папку с файлами конфигурации можно добавить следующие файлы:
- В файле `meta.json` можно описать свойства теста (все поля опциональны):
    ```yaml
    # имя теста
    name: str
    # описание теста
    description: str
    # лейблы теста
    labels: {"test-label": "value"}
    # лейблы агентов, на которых тест нужно запускать
    agent_labels: {"agent-label": "value"}
    # количество агентов на каждый файл с конфигурацией
    multi: 1 
    # массив с описанием откуда брать внешние файлы (вне репозитория)
    external_data: [{"name": "", "s3bucket": "", "s3file": ""}]
    ```
- В файле `check_summary.sh` можно написать валидацию `yc loadtesting test get $test_id`
- В файле `check_report.sh` можно написать валидацию `yc loadtesting test get-report-tables $test_id`

---

### Конфигурация теста через `meta.json`

Некоторые настройки теста можно определить в файле `meta.json`.

- имя теста:

    ```json
    {
        "name": "smoke"
    }
    ```
- описание теста:

    ```json
    {
        "description": "If this test fails... ALARM!!!!!!!!!"
    }
    ```
- метки теста:
    ```json
    {
        "labels": {
            "k1": "v1",
            "k2": "v2"
        }
    }
    ```
- требования к агенту, через спецификацию меток, которые должны быть у него проставлены:
    ```json
    {
        "agent_labels": {
            "net": "1gb",
            "disk": "ssd"
        }
    }
    ```

---

### Передача тестовых данных на агент

#### Из репозитория:

_Так как, в общем случае, скачивание агентом файлов напрямую из репозитория невозможно, необходимо использовать промежуточное хранилище, к которому будет доступ и у агента, и у CI. В качестве такого промежуточного хранилища предлагается использовать Object Storage._

При указании имени бакета через переменную среды `YC_LT_DATA_BUCKET`:
1. все дополнительные файлы в папке с тестом загружаются в бакет `YC_LT_DATA_BUCKET` (т.е. все файлы, кроме служебных `meta.json`, `config*.yaml` и т.д.)
2. для передачи списка необходимых файлов агенту, информация о них добавляется в запрос на создание теста
3. по завершении теста, загруженные на первом шаге файлы удаляются из бакета

_**WARNING: У сервисного аккаунта, с которым запускается агент, должны быть права на чтение файлов из этого бакета.**_  
_**WARNING2: У сервисного аккаунта, от лица которого создаются тесты, должны быть права на загрузку файлов в этот бакет.**_

#### Из бакета Object Storage:

_Данный способ подходит в тех случаях, когда вы планируете использовать тестовые данные, которые изначально хранятся в Object Storage_

В файле `meta.json` можно описать секцию `external_data`, в которой должно быть определен список из структур, определяющих имя бакета, имя файла в бакете, и имя, которое агент даст файлу при скачивании.

_**WARNING: У сервисного аккаунта, с которым запускается агент, должны быть права на чтение файлов из указанных бакетов.**_

Пример:
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

### Запуск теста на нескольких агентах одновременно (мультитест)

В файле `meta.json` можно указать параметр `multi`, присвоив ему значение, равное желаемому количеству агентов, на которых тест будет выполняться одновременно.

```json
{
    "multi": 3
}
```

_**WARNING: если на момент запуска теста, необходимое количество агентов не будет подключено к сервису, тест не запустится.**_

---

### Валидация результатов проведенного теста в CI

По умолчанию, система запуска уже выполняет некоторые проверки. В каждом тесте эти проверки можно переопределить, добавив в папку с тестом проверочные скрипты `check_summary.sh` и `check_result.sh`.

По завершению выполнения теста, эти скрипты будут вызваны в виде, аналогичном следующему:

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

Тест считается упавшим, если один из скриптов завершился с ошибкой (`exit_code != 0`).

_**Прим: полностью выключить проверки можно, указав YC_LT_SKIP_TEST_CHECK=1**_
