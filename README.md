# review.nvim

리뷰 설명·판정·코드 위치를 사용자 로컬 JSON에 저장하는 Neovim 플러그인입니다. 소스에는 주석을 넣지 않고 가상 텍스트와 배경 강조로 표시합니다. **리뷰 진입·판정·종료는 소스를 수정하거나 저장하지 않습니다.**

Neovim 0.10 이상을 사용합니다. 검색창은 Telescope·Plenary, 기존 주석의 프로젝트 전체 이전은 ripgrep이 필요합니다.

## 빠른 시작

AI가 작성한 코드를 훑으며 확인할 부분을 찾고, 직접 수정하거나 OK / REJECT 판정을 남기는 개인 리뷰 도구입니다. GitHub PR 리뷰를 게시하거나 자동으로 코드를 평가하지 않습니다.

1. 아래 lazy.nvim 설정으로 설치합니다.
2. 코드 범위를 선택하고 `:ReviewAdd 확인할 내용`으로 리뷰 항목을 만듭니다. AI 도구에서는 아래 동기화 API를 사용할 수 있습니다.
3. `<leader>fr`로 항목을 검색하고 Enter로 코드에 이동합니다.
4. `<leader>ro` / `<leader>rx`로 판정하고, `<leader>rv`로 리뷰를 잠시 끈 뒤 코드를 수정합니다.

## 설치

[lazy.nvim](https://github.com/folke/lazy.nvim) 플러그인 설정:

```lua
{
  "dukjjang/review.nvim",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  cmd = { "Review", "ReviewBuffer", "ReviewStop", "ReviewPick", "ReviewAdd", "ReviewRelocate", "ReviewImport", "ReviewImportBuffer" },
  keys = { "<leader>rv", "<leader>fr", "]r", "[r", "<leader>ro", "<leader>rx", "<leader>ru" },
  opts = { auto_advance = true },
}
```

## 새 리뷰 등록

코드의 줄 범위를 Visual로 선택한 뒤 다음 명령을 실행합니다. 범위를 선택하지 않으면 현재 줄에 등록합니다.

```vim
:'<,'>ReviewAdd 버튼 노출 조건과 돌아가기 동작 확인
```

Lua에서는 현재 파일을 대상으로 `require("review").add("설명", 시작줄, 끝줄)`을 사용할 수 있습니다. 이름 있는 소스 버퍼가 필요합니다. 미저장 코드에 등록해도 버퍼를 저장하지 않습니다. 해당 코드가 디스크에 저장되기 전 다른 프로세스에서는 위치를 찾지 못할 수 있습니다.

코드를 생성하는 AI도 `REVIEW`, `REVIEW[OK]`, `REVIEW[REJECT]`, `REVIEW_END` 주석을 만들지 않아야 합니다. 리뷰를 대화로 전달하거나 위 API로 등록합니다.

## 사용

| 키 / 명령 | 동작 |
| --- | --- |
| `<leader>rv` | 리뷰 모드 진입·일시 중지·마지막 지점 재개 |
| `<leader>fr` / `:ReviewPick` | 상태·파일명·설명 검색, Enter로 이동 |
| `]r` / `[r` | 위치가 확인된 다음·이전 리뷰로 순환 이동 |
| `<leader>ro` | OK 판정 |
| `<leader>rx` | REJECT 판정 |
| `<leader>ru` | PENDING으로 초기화 |
| `:Review` / `:Review /path/to/project` | 로컬 리뷰 데이터 다시 읽기 |
| `:ReviewBuffer` | 현재 파일의 리뷰만 표시 |
| `:ReviewStop` | 리뷰 종료 및 재개 위치 초기화. 판정 데이터 유지 |

미검토는 주황색, 합격은 녹색, 불합격은 붉은색입니다. 설명은 코드 위의 가상 줄로 보이며 저장 파일에는 포함되지 않습니다. 우측 상단에는 `OK / PENDING / REJECT` 개수가 표시됩니다. 오른쪽 고정 목록은 없습니다.

판정은 즉시 로컬 파일에 저장되므로 `:w`가 필요 없습니다. 코드의 undo 기록에도 들어가지 않습니다. 판정을 되돌리려면 `<leader>ru`를 사용합니다. 직접 편집한 코드는 기존처럼 사용자가 저장해야 합니다. 리뷰를 종료한 뒤 codex-nvim으로 수정 요청을 보내도 리뷰 판정 때문에 미저장 버퍼가 생기지 않습니다.

## 코드 변경 후 위치 확인

등록 시 선택한 코드 내용을 anchor로 보관합니다. 줄이 추가되어도 동일한 코드 범위가 유일하게 존재하면 위치를 다시 찾습니다. 코드 내용이 달라지거나 같은 범위가 여러 곳에 존재하거나 파일이 사라졌다면 **위치 재확인**으로 표시하고 강조·자동 이동에서 제외합니다. 확실하지 않은 위치로 임의로 이동하지 않습니다.

`<leader>fr`에서 위치 재확인 항목을 선택하면 재연결 대상으로 기억합니다. 올바른 파일과 코드 범위를 선택하고 `:'<,'>ReviewRelocate`를 실행하세요. 새 위치를 저장하고 판정은 PENDING으로 초기화합니다. `:ReviewRelocate 항목ID`로 직접 지정할 수도 있습니다.

리뷰 모드가 켜져 있으면 다른 Neovim이나 도구의 로컬 데이터 변경을 감지해 표시를 갱신합니다. 수동으로 다시 읽으려면 `:Review` 또는 `<leader>fr`를 사용하세요. 오래된 상태로 다른 프로세스의 판정을 덮어쓰지 않도록 저장 충돌을 검사합니다.

## 기존 REVIEW 주석 이전

일반 리뷰 진입으로 소스를 변경하지 않습니다. 이전 명령을 한 번 실행해야 합니다.

```vim
:ReviewImportBuffer
" 또는 현재 프로젝트의 기존 주석 전체 이전
:ReviewImport
```

이전 순서:

1. 원본 파일과 현재 버퍼 내용을 로컬 백업에 기록하고 확인합니다.
2. 설명·기존 판정·주석을 제거한 뒤의 코드 범위를 로컬 JSON에 저장합니다.
3. 저장이 성공한 파일에서만 기존 마커 줄을 제거합니다.

처음부터 깨끗했던 파일은 주석 제거를 저장합니다. 미저장 코드가 있던 파일은 버퍼에서 마커만 제거하고 **기존 코드 편집을 자동 저장하지 않습니다**. 내용 확인 후 `:w`로 저장하세요. 백업이나 데이터 저장이 실패하면 원본 주석을 보존합니다. 이전을 반복해도 같은 항목을 중복 등록하지 않습니다.

지원하는 기존 표기는 독립된 주석 줄의 `REVIEW: 설명`, `REVIEW[OK]: 설명`, `REVIEW[REJECT]: 설명`, `REVIEW_END`입니다. 마커가 없는 프로젝트를 주석 검색만으로 새 리뷰로 만들지는 않습니다. 이전 파서는 주석 접두사를 이용하므로, 문자열 안에 실제 마커처럼 적힌 예제 코드는 이전 대상에서 제외하세요. 범위가 명확하지 않은 기존 주석은 이전 후 검색창에서 확인하세요.

## 데이터 위치와 백업

```text
stdpath("data")/review/
  <프로젝트 절대 경로의 SHA-256>.json
  backups/<프로젝트 경로 해시>/
    <해시>.source       # 이전 전 디스크 원본
    <해시>.buffer.json  # 이전 전 버퍼 원본
```

일반적인 macOS 위치는 `~/.local/share/nvim/review/`입니다. Git 작업 폴더 밖에 있으며 커밋에 포함되지 않습니다. 이 디렉터리는 리뷰 설명과 코드 발췌를 포함하므로 본인이 필요할 때 별도로 백업하세요. worktree는 절대 경로별로 분리됩니다. 저장소 경로를 이동하면 이전 데이터의 `root`와 저장 파일 이름도 함께 이전해야 합니다.

JSON은 `version: 1`, `root`, `items`로 구성됩니다. 각 항목은 `id`, 프로젝트 상대 `path`, `title`, `status`, 1부터 시작하는 `row`, 선택한 코드 줄 배열 `anchor`를 가집니다. 직접 JSON을 편집하기보다 명령/API를 권장합니다. JSON 손상이나 저장 충돌은 알림으로 표시하고 조용히 초기화하지 않습니다.

## 설정과 검증

```lua
require("review").setup({ auto_advance = true, keymaps = true })
```

`auto_advance`는 판정 후 다음 미검토 항목으로 이동합니다. `keymaps = false`이면 기본 키맵을 등록하지 않습니다. `ReviewPending`, `ReviewOK`, `ReviewReject`, `ReviewSummary`, `ReviewCountOK`, `ReviewCountPENDING`, `ReviewCountREJECT`로 표시 색상을 조정할 수 있습니다.

```sh
nvim --headless -u NONE -l tests/review_test.lua
nvim --headless -u NONE -l tests/migration_test.lua
nvim --headless -u NONE -l tests/toggle_test.lua
nvim --headless -u NONE -l tests/summary_test.lua
nvim --headless -u NONE -l tests/lazy_scan_test.lua
nvim --headless -u NONE -l tests/modeline_test.lua
nvim --headless -u NONE -l tests/picker_test.lua
nvim --headless -u NONE -l tests/sync_test.lua
# 선택: codex-cli.nvim 연동 검증
nvim --headless -u NONE -l tests/codex_handoff_test.lua
```

검색 테스트는 실제 Telescope·Plenary를 사용합니다. 설치 위치가 `stdpath("data")/lazy`가 아니면 `REVIEW_TEST_PLUGINS`를 지정합니다. Codex 연동 테스트는 인접한 `../codex-cli.nvim`을 사용하며 다른 경로는 `REVIEW_TEST_CODEX`로 지정합니다. 테스트는 임시 로컬 데이터와 모의 App Server를 사용하고 실제 모델 호출이나 프로젝트 커밋은 실행하지 않습니다.

## AI 변경사항 동기화

`require("review.sync").apply(request)` 또는 headless 진입점으로 로컬 리뷰를 갱신할 수 있습니다. 특정 AI나 개인 스킬 설치에는 의존하지 않습니다.

```sh
nvim --headless -u NONE -i NONE -l /path/to/review.nvim/scripts/sync.lua /tmp/review-request.json
```

예를 들어 아래 JSON을 임시 파일에 작성하고 위 명령에 전달합니다. 경로와 줄 범위는 실제 저장된 코드에 맞춰 지정하세요.

```json
{
  "root": "/absolute/path/to/project",
  "task": "settings-validation",
  "items": [
    {
      "key": "invalid-input",
      "path": "src/settings.ts",
      "first": 12,
      "last": 24,
      "title": "잘못된 입력의 저장을 차단하도록 변경. 오류 표시와 재입력 후 저장 확인."
    }
  ]
}
```

성공하면 생성·갱신·유지·보관 개수와 데이터 경로를 JSON으로 출력하고, 실패하면 0이 아닌 종료 코드를 반환합니다. 파일을 저장한 뒤 호출하세요. AI가 작업 종료 시 이 API를 실행하도록 사용하는 도구의 개인 지침에 연결하면 됩니다. 이 플러그인은 AI 작업을 자동 감시하거나 특정 스킬을 설치하지 않습니다.

요청은 `root`(프로젝트 절대 경로), `task`(안정적인 작업 키), `items`를 포함합니다. 각 항목에는 `key`(작업 내 안정적인 키) 또는 기존 `id`, `path`(프로젝트 상대 경로), `first`·`last`(줄 범위), `title`을 지정합니다. 도구가 현재 디스크에서 코드를 읽어 anchor를 생성합니다.

- 새 항목은 PENDING이며 같은 task/key는 같은 ID를 사용합니다.
- 코드·설명·대상 파일이 바뀌면 PENDING으로 되돌립니다. 줄 위치만 바뀌면 기존 판정을 유지합니다.
- 생략한 항목은 유지합니다. `archive: [{"id":"...","reason":"기능 삭제"}]`로 지정한 항목만 현재 목록에서 숨기고 데이터는 보존합니다.
- 잘못된 범위·프로젝트 밖 경로·동시 저장 충돌은 요청 전체를 실패 처리합니다.

리뷰 모드에서는 로컬 JSON 변경을 감지해 강조·카운터·열린 검색 결과를 갱신합니다. 소스는 수정하거나 저장하지 않습니다.

검증: `nvim --headless -u NONE -l tests/sync_test.lua`.
