# Release — assinatura, notarização e DMG (T-25)

O Tomafoco é distribuído **fora da Mac App Store** (ADR-2). Isso significa que o macOS só
abre o app em outra máquina se ele estiver **assinado com Developer ID** e **notarizado** pela
Apple. Sem os dois, o usuário final vê "app danificado / não pode ser aberto" e não há como
contornar sem instruções de bypass — que ninguém deveria seguir.

Todo o empacotamento está em [`scripts/release.sh`](../scripts/release.sh).

```bash
./scripts/release.sh                  # pipeline completo
SKIP_NOTARIZE=1 ./scripts/release.sh  # para no DMG (teste local do empacotamento)
```

---

## Pré-requisitos (feitos UMA vez)

### 1. Apple Developer Program

Certificado Developer ID exige a assinatura paga (US$ 99/ano). Conta gratuita **não** emite
esse tipo de certificado — só "Apple Development", que serve apenas para rodar localmente.

### 2. Certificado "Developer ID Application"

1. https://developer.apple.com/account/resources/certificates → **+**
2. Escolha **Developer ID Application**
3. Suba um CSR gerado no *Acesso às Chaves* (Assistente de Certificação → Solicitar
   Certificado a uma Autoridade) e instale o `.cer` baixado.

Confirme:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 3. Credencial de notarização

O `release.sh` lê a credencial de um **perfil no chaveiro** chamado `tomafoco`. Existem dois
jeitos de criar esse perfil — o de chave de API é o recomendado.

#### Opção A — chave de API do App Store Connect (recomendado)

Não envolve Apple ID, senha nem 2FA, e não quebra quando a senha da conta muda.

1. https://appstoreconnect.apple.com/access/integrations/api → **+**
2. Função **Developer**; baixe o `AuthKey_XXXXXXXX.p8` (**só é possível baixar uma vez**)
3. Anote o **Key ID** (no nome do arquivo) e o **Issuer ID** (topo da página)

```bash
xcrun notarytool store-credentials tomafoco \
  --key ~/private_keys/AuthKey_XXXXXXXX.p8 \
  --key-id XXXXXXXX \
  --issuer 00000000-0000-0000-0000-000000000000
```

Guarde o `.p8` fora do repositório (ex.: `~/private_keys/`, permissão `600`). Quem tiver esse
arquivo pode agir na sua conta do App Store Connect.

#### Opção B — senha específica de app

```bash
xcrun notarytool store-credentials tomafoco    # modo interativo: a senha não vai para o histórico
```

Responda: Apple ID (e-mail), senha específica de app (formato `abcd-efgh-ijkl-mnop`, gerada em
appleid.apple.com → Segurança), Team ID `CJQ7T4KV7H`.

> Nunca passe `--password` na linha de comando: a senha fica no histórico do shell e o zsh ainda
> pode interpretar `!` e `$` antes de o comando recebê-la.

#### Erro 401 "Invalid credentials"

Em ordem de probabilidade:

1. A senha específica de app foi gerada em **outra Apple ID** (o navegador estava logado em outra conta).
2. A senha foi passada por `--password` e o shell alterou algum caractere.
3. A senha da conta Apple foi usada no lugar da específica de app — com 2FA, sempre falha.
4. Há **contrato pendente** de aceite em https://developer.apple.com/account (banner no topo).
5. O Apple ID não é membro do time `CJQ7T4KV7H`.

Se persistir, use a Opção A: ela não passa por nenhum desses caminhos.

---

## O que o script faz

| Passo | Por quê |
|---|---|
| `xcodebuild -configuration Release` | build sem assinatura (`CODE_SIGNING_ALLOWED=NO`) |
| `codesign --options runtime --timestamp` | Hardened Runtime + carimbo de tempo — a notarização **rejeita** sem os dois |
| `--entitlements Tomafoco.entitlements` | preserva o `apple-events`, sem o qual o bloqueio de sites para de funcionar |
| `hdiutil create` | DMG com o app + atalho para `/Applications` |
| `codesign` no DMG | Gatekeeper também avalia o container |
| `notarytool submit --wait` | envia e aguarda o veredito da Apple (minutos) |
| `stapler staple` | grava o ticket no DMG: passa a abrir **offline** |
| `spctl --assess` | simula localmente o que o Gatekeeper fará na máquina do usuário |

---

## Verificar o resultado

```bash
spctl --assess --type open --context context:primary-signature -v build/Tomafoco-1.0.dmg
# esperado: accepted / source=Notarized Developer ID
```

Teste real: copie o DMG para **outro** Mac (ou remova o atributo de quarentena local com
`xattr -d com.apple.quarantine`, que mascara o problema) e abra. Um DMG que abre na máquina
que o construiu não prova nada — ali o app já é confiável por ter sido compilado localmente.

---

## Notas

- **Certificado Apple Development vence em 2026-08-10.** Ele não serve para distribuir, mas é o
  que permite rodar localmente; renove antes para não travar o desenvolvimento.
- Se a notarização for rejeitada, o motivo detalhado vem em:
  ```bash
  xcrun notarytool log <submission-id> --keychain-profile tomafoco
  ```
- A versão do DMG sai de `MARKETING_VERSION` no `project.yml` — subir versão é editar lá.
- O app **não** embarca mais nenhum daemon privilegiado (ADR-8), o que simplifica a notarização:
  não há binário aninhado para assinar separadamente.
