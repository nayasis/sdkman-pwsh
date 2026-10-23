# SDKMAN! for PowerShell

[English](README.md) | 한국어

Windows에서 bash나 Cygwin 없이 SDK 버전을 관리하는 [SDKMAN!](https://sdkman.io)의 PowerShell 포트입니다.

- Windows PowerShell 5.1 및 PowerShell 7+ 지원
- 공식 SDKMAN API 사용 및 기존 `~/.sdkman` 디렉터리 공유 가능
- 탭 자동완성과 `.sdkmanrc` 기반 프로젝트 환경 지원

## 설치

```powershell
git clone https://github.com/nayasis/sdkman-pwsh.git
cd sdkman-pwsh
.\install.ps1
```

설치 경로는 `-SdkmanDir <path>`로 지정합니다. 
- 기본값은 `$env:SDKMAN_DIR` 또는 `~/.sdkman`

실행 정책 이슈로 설치가 실패하면, 다음 명령어를 실행해 주세요.

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 사용법

```powershell
sdk list                        # SDK 목록
sdk list java                   # 설치 가능한 Java 버전
sdk install java                # 권장 버전 설치
sdk use java <version>          # 현재 셸의 버전 전환
sdk default java <version>      # 새 셸에서 사용할 기본 버전 설정
sdk current                     # 사용 중인 버전 확인
sdk uninstall java <version>    # 버전 제거
sdk help                        # 전체 명령 확인
```

`<version>`은 `sdk list java`에 표시된 버전 식별자로 바꿉니다. 로컬 SDK는 `sdk install java 17-local C:\jdks\jdk-17`로 등록합니다.

프로젝트별 SDK 버전 고정:

```powershell
sdk env init       # 현재 버전으로 .sdkmanrc 생성
sdk env install    # .sdkmanrc에 지정한 버전 설치
sdk env            # 프로젝트 환경 적용
sdk env clear      # 기본 버전으로 복원
```

명령은 성공 시 `$LASTEXITCODE`를 `0`, 실패 시 `1`로 설정합니다. `sdk home <candidate> <version>`은 설치 경로를 파이프라인 값으로 반환합니다.

## 설정

`sdk config`로 `~/.sdkman/etc/config`를 편집합니다. 주요 설정은 다음과 같습니다.

| 설정 | 기본값 | 설명 |
| --- | --- | --- |
| `sdkman_auto_answer` | `false` | 확인 질문에 자동으로 동의 |
| `sdkman_auto_complete` | `true` | 탭 자동완성 사용 |
| `sdkman_auto_env` | `false` | 디렉터리 이동 시 `.sdkmanrc` 자동 적용 |
| `sdkman_checksum_enable` | `true` | API가 제공하는 체크섬 검증 |
| `sdkman_colour_enable` | `true` | 색상 출력 사용 |

Oh My Posh나 Starship과 자동 환경 전환을 함께 쓰려면 프로필에서 SDKMAN의 `Import-Module` 줄을 프롬프트 설정 뒤에 배치합니다.

## 호환성과 업데이트

`current`에는 디렉터리 정션을 사용하며, tar 압축 해제에는 Windows의 `tar.exe`가 필요합니다.

기존 Git Bash 설치의 `current`가 복사본이라면 `sdk default <candidate> <version>`을 실행해 정션으로 바꿉니다.

`sdk selfupdate`와 bash의 `ext/` 스크립트는 지원하지 않습니다. 모듈을 업데이트하려면 저장소를 최신 상태로 갱신하고 `.\install.ps1`을 다시 실행합니다.

## 제거

`.\uninstall.ps1`은 설치한 SDK를 보존하고 모듈과 프로필 설정을 제거합니다.

`-RemoveSdkmanDir`을 추가하면 SDK, 설정, 캐시를 포함한 SDKMAN 디렉터리 전체를 삭제합니다.

## 테스트

스모크 테스트는 임시 `SDKMAN_DIR`에서 실제 API로 Apache Ant를 설치·전환·제거합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Sdkman.ps1
pwsh -NoProfile -File tests\Test-Sdkman.ps1
```
