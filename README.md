# SDKMAN! for PowerShell

[SDKMAN!](https://sdkman.io)을 PowerShell로 포팅한 모듈입니다. 원본 bash 구현(`sdkman-cli` 5.x)의 명령, 출력, 디렉터리 구조, 설정 파일을 그대로 따르면서 Windows에서 bash/Cygwin 없이 동작합니다.

- Windows PowerShell 5.1과 PowerShell 7+ 지원
- SDKMAN 공식 API(`https://api.sdkman.io/2`, 플랫폼 `windowsx64`) 사용
- 기존 bash SDKMAN과 같은 `~/.sdkman` 디렉터리를 공유할 수 있음 (candidates, `etc/config`, `var/candidates` 형식 호환)

## 설치

```powershell
git clone <this repo> C:\project\sdkman   # 또는 압축 해제
cd C:\project\sdkman
.\install.ps1
```

`install.ps1`이 하는 일:

1. `$env:SDKMAN_DIR`(기본값 `~\.sdkman`) 아래에 `candidates`, `tmp`, `etc`, `var` 등을 만들고 `etc\config`, `var\platform`, `var\candidates`가 없으면 생성합니다.
2. 모듈을 `~\.sdkman\pwsh\Sdkman`에 복사합니다.
3. Windows PowerShell(`Documents\WindowsPowerShell\profile.ps1`)과 PowerShell 7(`Documents\PowerShell\profile.ps1`) 프로필에 `Import-Module` 줄을 추가합니다.

옵션:

| 옵션 | 설명 |
| --- | --- |
| `-SdkmanDir <path>` | SDKMAN 홈 디렉터리 지정 |
| `-NoProfile` | 프로필을 수정하지 않고, 추가할 내용만 출력 |

실행 정책이 `Restricted`이면 프로필이 로드되지 않습니다. 이때는 다음을 먼저 실행하세요.

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

제거: `.\uninstall.ps1` (모듈과 프로필 설정만 제거합니다. 설치한 SDK까지 지우려면 `-RemoveSdkmanDir`)

## 사용법

```powershell
sdk list                       # 전체 candidate 목록
sdk list java                  # java 버전 목록
sdk install java               # 기본(최신 안정) 버전 설치
sdk install java 21.0.5-tem    # 특정 버전 설치
sdk install java 17-local C:\jdks\jdk-17   # 로컬 설치본 연결
sdk use java 21.0.5-tem        # 현재 셸에서만 전환 (JAVA_HOME, PATH)
sdk default java 21.0.5-tem    # 기본 버전 변경 (모든 셸)
sdk current [java]             # 사용 중인 버전
sdk home java 21.0.5-tem       # 설치 경로 출력 (파이프라인 값으로 반환)
sdk uninstall java 21.0.5-tem
sdk upgrade [java]             # 기본 버전보다 오래된 candidate 업그레이드
sdk env init | install | clear # .sdkmanrc 기반 프로젝트별 환경
sdk offline [enable|disable]
sdk update                     # candidate 목록 갱신
sdk flush [tmp|metadata|version]
sdk config                     # $env:EDITOR(없으면 notepad)로 etc\config 열기
sdk version
sdk help
```

단축 명령도 같습니다: `i`, `rm`, `l`/`ls`, `u`, `d`, `h`, `e`, `c`, `ug`, `v`.

탭 자동완성으로 명령, candidate, 버전을 채울 수 있습니다. `install`은 원격 버전, `use`/`default`/`home`/`uninstall`은 설치된 버전을 제안합니다.

각 명령은 성공하면 `$LASTEXITCODE`를 `0`, 실패하면 `1`로 설정하므로 스크립트에서 결과를 확인할 수 있습니다.

## 설정 (`~\.sdkman\etc\config`)

bash 버전과 같은 키를 사용합니다.

| 키 | 기본값 | 설명 |
| --- | --- | --- |
| `sdkman_auto_answer` | `false` | 확인 질문에 자동으로 Yes |
| `sdkman_auto_complete` | `true` | 탭 자동완성 등록 |
| `sdkman_auto_env` | `false` | 디렉터리 이동 시 `.sdkmanrc`를 자동 적용 (prompt 훅) |
| `sdkman_checksum_enable` | `true` | API가 제공하는 체크섬 검증 |
| `sdkman_colour_enable` | `true` | 색상 출력 |
| `sdkman_curl_max_time` | `10` | healthcheck/update 요청 타임아웃(초) |
| `sdkman_curl_retry` | `0` | 다운로드 재시도 횟수 |
| `sdkman_debug_mode` | `false` | 디버그 출력 |
| `sdkman_insecure_ssl` | `false` | TLS 인증서 검증 생략 |

`sdkman_auto_env`는 모듈을 가져올 때 `prompt` 함수를 감싸서 동작합니다. oh-my-posh나 starship처럼 prompt를 바꾸는 도구를 쓴다면, 그 설정 **뒤에** `Import-Module` 줄이 오도록 프로필 순서를 맞추세요.

## bash 버전과 다른 점

| 항목               | bash SDKMAN                               | PowerShell 포트                                                                       |
| ---------------- | ----------------------------------------- | ----------------------------------------------------------------------------------- |
| `current` 링크     | 심볼릭 링크 (Git Bash에서는 실제로 디렉터리 **복사본**)     | **디렉터리 정션** (관리자 권한 불필요). 네트워크 경로는 심볼릭 링크로 대체                                       |
| 환경 변경            | `export`                                  | 현재 프로세스의 `$env:PATH`, `$env:<CANDIDATE>_HOME`                                       |
| 다운로드             | curl + 원격 post-install hook(bash 스크립트) 실행 | .NET `HttpClient`. Windows용 hook은 파일 이름만 바꾸므로 실행하지 않고, 아카이브 형식(zip/tar.gz 등)을 직접 판별 |
| 압축 해제            | `unzip`                                   | zip은 `System.IO.Compression`, tar 계열은 Windows 내장 `tar.exe`                          |
| 체크섬              | `shasum`/`md5sum`                         | .NET 해시 (SHA-1/256/384/512, MD5)                                                    |
| `sdk home`       | stdout으로 출력                               | 파이프라인 값으로 반환 (`$h = sdk home java 21.0.5-tem`)                                      |
| `sdk list` 페이저   | `less`                                    | `$env:PAGER`가 있으면 사용, 없으면 그대로 출력 (`sdk list java | Select-String tem` 가능)           |
| `sdk selfupdate` | 지원                                        | 미지원 (`install.ps1`을 다시 실행해서 업데이트)                                                   |
| `ext/` 확장 스크립트   | 지원                                        | 미지원                                                                                 |

### 기존 bash SDKMAN과 함께 쓰기

같은 `~/.sdkman`을 공유하므로 bash로 설치한 SDK를 PowerShell에서 바로 `sdk use`할 수 있습니다. Git Bash가 만든 `current`는 링크가 아니라 복사본이라 PowerShell 쪽에서는 기본 버전을 알 수 없습니다. `sdk default <candidate> <version>`을 한 번 실행하면 정션으로 바뀝니다.

## 테스트

임시 `SDKMAN_DIR`을 만들어 실제 API로 Apache Ant를 설치·전환·삭제해 보는 E2E 스모크 테스트입니다. 기존 `~/.sdkman`은 건드리지 않습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Sdkman.ps1   # Windows PowerShell 5.1
pwsh -NoProfile -File tests\Test-Sdkman.ps1                                 # PowerShell 7
```

## 구조

```
install.ps1 / uninstall.ps1
src/Sdkman/
  Sdkman.psd1, Sdkman.psm1      # sdk 함수(sdkman-main.sh) + 초기화(sdkman-init.sh)
  completion.ps1                # 탭 자동완성
  lib/
    sdkman-utils.ps1            # 출력, 설정 로드
    sdkman-http.ps1             # HTTP(curl 대체), 다운로드 진행률
    sdkman-path-helpers.ps1     # 정션, PATH/HOME 관리
    sdkman-availability.ps1     # healthcheck, offline, 캐시 검사
    sdkman-env-helpers.ps1      # 버전 결정/검증
    sdkman-install.ps1          # 다운로드, 압축 해제, 체크섬, 로컬 설치
    sdkman-commands.ps1         # list/use/current/default/uninstall/home/flush/version/config/help
    sdkman-env.ps1              # .sdkmanrc, auto-env
    sdkman-upgrade.ps1          # upgrade/update
tests/Test-Sdkman.ps1
```
