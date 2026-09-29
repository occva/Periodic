import QuickLook
import SwiftUI

struct SubscriptionActivityView: View {
    @Environment(\.currencyDisplayStyle) private var currencyDisplayStyle
    @Environment(AppServices.self) private var services

    let payments: [SubscriptionPaymentDTO]
    let periods: [SubscriptionPeriodDTO]
    let isLoading: Bool
    let isDeleting: Bool
    let onEdit: @MainActor (SubscriptionPaymentDTO) -> Void
    let onDelete: @MainActor (SubscriptionPaymentDTO) -> Void

    @State private var previewSelection: URL?
    @State private var previewURLs: [URL] = []
    @State private var previewError: PresentedError?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在读取动态…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if payments.isEmpty {
                VStack(spacing: 8) {
                    Text("开始记录第一笔消费")
                        .font(.headline)
                    Text("实际支付、备注和截图会显示在这里")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                paymentList
            }
        }
        .quickLookPreview($previewSelection, in: previewURLs)
        .errorAlert($previewError)
    }

    private var paymentList: some View {
        let rows = payments.sorted {
            ($0.paymentDate.dayNumber, $0.createdAt, $0.id.uuidString)
                > ($1.paymentDate.dayNumber, $1.createdAt, $1.id.uuidString)
        }
        let periodPositions = Dictionary(
            uniqueKeysWithValues: periods.enumerated().map { ($0.element.id, $0.offset) }
        )
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, payment in
                    paymentRow(payment, periodPositions: periodPositions)
                    if index < rows.index(before: rows.endIndex) {
                        Divider().padding(.leading, 132)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func paymentRow(
        _ payment: SubscriptionPaymentDTO,
        periodPositions: [UUID: Int]
    ) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(payment.paymentDate.displayText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 96, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(payment.kind.title)
                        .font(.headline)
                    Text(payment.money.displayText(style: currencyDisplayStyle))
                        .font(.headline)
                        .monospacedDigit()
                    Spacer()
                    Button("编辑") { onEdit(payment) }
                        .buttonStyle(.plain)
                    Button("删除", role: .destructive) { onDelete(payment) }
                        .buttonStyle(.plain)
                }
                if let description = periodDescription(
                    for: payment,
                    periodPositions: periodPositions
                ) {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !payment.note.isEmpty {
                    Text(payment.note)
                        .textSelection(.enabled)
                }
                if !payment.attachmentReferences.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(payment.attachmentReferences, id: \.self) { reference in
                                Button {
                                    previewAttachment(
                                        reference,
                                        in: payment.attachmentReferences
                                    )
                                } label: {
                                    PaymentAttachmentImageView(
                                        reference: reference,
                                        maximumSize: CGSize(width: 420, height: 240)
                                    )
                                        .background(
                                            .quaternary,
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("预览消费截图")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .disabled(isDeleting)
    }

    private func periodDescription(
        for payment: SubscriptionPaymentDTO,
        periodPositions: [UUID: Int]
    ) -> String? {
        if let periodID = payment.periodRecordID,
           let index = periodPositions[periodID] {
            return String(
                format: AppLocalization.string("关联第 %d 个周期 · %@"),
                index + 1,
                periods[index].paymentPickerTitle
            )
        }
        guard let start = payment.periodStart, let end = payment.periodEnd else { return nil }
        return String(
            format: AppLocalization.string("覆盖周期 %@ – %@"),
            start.displayText,
            end.displayText
        )
    }

    private func previewAttachment(_ reference: String, in references: [String]) {
        Task { @MainActor in
            do {
                let urls = try await services.paymentAttachmentStore.previewURLs(
                    for: references
                )
                guard let selectedIndex = references.firstIndex(of: reference) else { return }
                previewURLs = urls
                previewSelection = urls[selectedIndex]
            } catch {
                previewError = PresentedError(error, title: "无法显示截图")
            }
        }
    }
}
