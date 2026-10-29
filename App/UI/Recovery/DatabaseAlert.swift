import AppKit

/// Avisos do banco de dados no lançamento (FEAT-006), via `LaunchAlert` (mesmo motivo do
/// `RecoveryAlert`: app só barra de menus, sem janela para um `.sheet`). Entram na fila e
/// aparecem depois de o app terminar de subir, um por vez.
@MainActor
enum DatabaseAlert {

    static func presentUnavailable(error: Error) {
        present(
            title: "Banco de dados indisponível",
            text: """
                Não foi possível abrir nem criar o banco de dados do Tomafoco. O app vai funcionar, \
                mas nada do que você fizer agora será salvo.

                \(error.localizedDescription)
                """)
    }

    static func presentReset() {
        present(
            title: "O banco de dados foi recriado",
            text: """
                O banco de dados do Tomafoco não abriu e foi preservado com a extensão .bak-<data> \
                em ~/Library/Application Support/Tomafoco. Um banco novo foi criado a partir da \
                última migração dos arquivos antigos — o que foi feito depois dela pode estar faltando.
                """)
    }

    static func presentMigrationFailed(error: Error) {
        present(
            title: "Não foi possível migrar seus dados",
            text: """
                Suas tarefas e seu histórico continuam nos arquivos antigos e a migração será \
                tentada de novo na próxima vez que o app abrir.

                \(error.localizedDescription)
                """)
    }

    static func presentUnreadableFiles(_ names: [String]) {
        present(
            title: "Alguns dados não puderam ser migrados",
            text: """
                Estes arquivos estavam ilegíveis e foram preservados com a extensão .bak em \
                ~/Library/Application Support/Tomafoco: \(names.joined(separator: ", ")). \
                O restante foi migrado normalmente.
                """)
    }

    /// Nem o banco em memória abriu — não há como o app funcionar. Modal **síncrono** (o app
    /// ainda está subindo; um alerta assíncrono não apareceria) e encerra.
    static func presentFatalAndExit(error: Error) -> Never {
        LaunchAlert.runNow(
            style: .critical,
            title: "O Tomafoco não pôde iniciar",
            text: """
                O banco de dados não abriu nem em disco nem em memória. Reinstale a versão mais \
                recente; se continuar, envie este erro:

                \(error.localizedDescription)
                """)
        exit(EXIT_FAILURE)
    }

    private static func present(title: String, text: String) {
        LaunchAlert.show(style: .warning, title: title, text: text)
    }
}
