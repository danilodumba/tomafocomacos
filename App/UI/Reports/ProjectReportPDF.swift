import AppKit
import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// Gera o PDF do relatório de projeto (RF-10.7) em páginas A4. Cada página é uma View SwiftUI
/// desenhada num contexto PDF pelo `ImageRenderer` — texto continua texto (selecionável,
/// nítido na impressão). Paginação manual: linhas de altura fixa, cabeçalho grande só na 1ª
/// página e o bloco do total sempre cabe na última.
@MainActor
enum ProjectReportPDF {

    static let pageSize = CGSize(width: 595, height: 842) // A4 em pontos
    static let margin: CGFloat = 40
    static let rowHeight: CGFloat = 22
    fileprivate static let firstHeaderHeight: CGFloat = 132
    fileprivate static let headerHeight: CGFloat = 48
    fileprivate static let tableHeaderHeight: CGFloat = 26
    fileprivate static let footerHeight: CGFloat = 24
    fileprivate static let totalBlockHeight: CGFloat = 84

    static func render(_ report: ProjectReport, period: ReportPeriod, generatedAt: Date) -> Data {
        let pages = paginate(report.rows)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        for (index, rows) in pages.enumerated() {
            let page = ProjectReportPDFPage(
                report: report, rows: rows, period: period, generatedAt: generatedAt,
                pageNumber: index + 1, pageCount: pages.count)
                .frame(width: pageSize.width, height: pageSize.height)
                // Papel é branco: tema claro fixo, independente do tema do app.
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: page)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    /// Fatia as linhas por página. A 1ª tem o cabeçalho grande; toda página reserva o rodapé; a
    /// última precisa caber o bloco do total — se não couber, ele vai sozinho para uma página nova.
    static func paginate(_ rows: [ProjectReport.Row]) -> [[ProjectReport.Row]] {
        func capacity(first: Bool) -> Int {
            let header = first ? firstHeaderHeight : headerHeight
            let available = pageSize.height - 2 * margin - header - tableHeaderHeight - footerHeight
            return max(1, Int(available / rowHeight))
        }
        var pages: [[ProjectReport.Row]] = []
        var remaining = rows[...]
        repeat {
            let take = capacity(first: pages.isEmpty)
            pages.append(Array(remaining.prefix(take)))
            remaining = remaining.dropFirst(take)
        } while !remaining.isEmpty
        let lastFits = CGFloat(pages.last?.count ?? 0) * rowHeight + totalBlockHeight
            <= CGFloat(capacity(first: pages.count == 1)) * rowHeight
        if !lastFits { pages.append([]) }
        return pages
    }
}

/// Uma página A4 do relatório. Cores fixas de papel (sem tokens adaptativos).
private struct ProjectReportPDFPage: View {
    let report: ProjectReport
    let rows: [ProjectReport.Row]
    let period: ReportPeriod
    let generatedAt: Date
    let pageNumber: Int
    let pageCount: Int

    private let ink = Color(hex: 0x1F2937)
    private let muted = Color(hex: 0x6B7280)
    private let rule = Color(hex: 0xE5E7EB)
    private var accent: Color { report.project.color.printColor }
    private var isFirst: Bool { pageNumber == 1 }
    private var isLast: Bool { pageNumber == pageCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirst { firstHeader } else { continuationHeader }
            if !rows.isEmpty || (isFirst && report.rows.isEmpty) {
                tableHeader
                ForEach(rows) { row($0) }
                if isFirst && report.rows.isEmpty {
                    Text("Nenhuma tarefa neste projeto.")
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                        .frame(height: ProjectReportPDF.rowHeight)
                }
            }
            if isLast { totalBlock }
            Spacer(minLength: 0)
            footer
        }
        .padding(ProjectReportPDF.margin)
        .background(Color.white)
    }

    // MARK: - Cabeçalhos

    private var firstHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RELATÓRIO DE PROJETO")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(muted)
            HStack(spacing: 8) {
                Image(systemName: report.project.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                Text(report.project.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
            Rectangle().fill(accent).frame(height: 3)
            HStack(spacing: 18) {
                meta("Período", period.printLabel)
                meta("Cadastro", day(report.project.createdAt))
                if let due = report.project.dueDate {
                    meta("Vencimento", day(due))
                }
                meta("Gerado em", generatedAt.formatted(Self.dateStyle.hour().minute()))
            }
            .padding(.top, 2)
            if let details = report.project.details {
                Text(details)
                    .font(.system(size: 9))
                    .foregroundStyle(muted)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .frame(height: ProjectReportPDF.firstHeaderHeight, alignment: .top)
    }

    private var continuationHeader: some View {
        HStack {
            Text(report.project.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(ink)
            Text("· continuação").font(.system(size: 11)).foregroundStyle(muted)
            Spacer()
        }
        .frame(height: ProjectReportPDF.headerHeight, alignment: .top)
    }

    /// Documento todo em português: datas em pt-BR fixo, não no idioma do sistema.
    private static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)
        .locale(Locale(identifier: "pt_BR"))

    private func day(_ date: Date) -> String { date.formatted(Self.dateStyle) }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 7, weight: .semibold)).tracking(0.8).foregroundStyle(muted)
            Text(value).font(.system(size: 10)).foregroundStyle(ink)
        }
    }

    // MARK: - Tabela

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("TAREFA").frame(maxWidth: .infinity, alignment: .leading)
            Text("SUBTAREFAS").frame(width: 64, alignment: .trailing)
            Text("SESSÕES").frame(width: 52, alignment: .trailing)
            Text("TEMPO").frame(width: 78, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(muted)
        .frame(height: ProjectReportPDF.tableHeaderHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 1) }
    }

    private func row(_ row: ProjectReport.Row) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if row.isCompleted {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(accent)
                }
                Text(row.title).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.subtaskCount > 0 ? "\(row.subtaskCount)" : "—").frame(width: 64, alignment: .trailing)
            Text("\(row.sessionCount)").frame(width: 52, alignment: .trailing)
            Text(ProjectReportsViewModel.formatDuration(row.focusTime))
                .fontWeight(.medium)
                .frame(width: 78, alignment: .trailing)
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(ink)
        .frame(height: ProjectReportPDF.rowHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 0.5) }
    }

    // MARK: - Total e rodapé

    private var totalBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total do projeto").font(.system(size: 11, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                Text(ProjectReportsViewModel.formatDuration(report.focusTotal))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ink)
            }
            HStack {
                Text("\(report.rows.count) tarefa(s) · \(report.sessionCount) sessão(ões) de foco")
                Spacer()
                Text(ProjectReportsViewModel.formatDecimalHours(report.focusTotal))
            }
            .font(.system(size: 9))
            .foregroundStyle(muted)
            if report.rowsSum > report.focusTotal {
                Text("Sessões com mais de uma tarefa do projeto contam uma vez no total (a soma das linhas é maior).")
                    .font(.system(size: 8))
                    .foregroundStyle(muted)
            }
        }
        .monospacedDigit()
        .padding(.top, 10)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .background(accent.opacity(0.08))
        .overlay(alignment: .top) { Rectangle().fill(accent).frame(height: 2) }
        .padding(.top, 10)
        .frame(height: ProjectReportPDF.totalBlockHeight, alignment: .top)
    }

    private var footer: some View {
        HStack {
            Text("Tomafoco")
            Spacer()
            Text("Página \(pageNumber) de \(pageCount)")
        }
        .font(.system(size: 8))
        .foregroundStyle(muted)
        .frame(height: ProjectReportPDF.footerHeight, alignment: .bottom)
    }
}
