//
//  ValidationErrorIndicator.swift
//  SwiftLintRuleStudio
//
//  Inline error display component for configuration validation
//

import SwiftUI

/// Displays validation errors and warnings inline
struct ValidationErrorIndicator: View {
    let errors: [ValidationResult.ValidationError]
    let warnings: [ValidationResult.ValidationWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(errors) { error in
                ValidationErrorRow(
                    icon: "xmark.circle.fill",
                    iconColor: .red,
                    field: error.field.description,
                    message: error.message,
                    suggestion: error.suggestion
                )
            }

            ForEach(warnings) { warning in
                ValidationErrorRow(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange,
                    field: warning.field.description,
                    message: warning.message,
                    suggestion: warning.suggestion
                )
            }
        }
    }
}

/// Single row for displaying a validation error or warning
struct ValidationErrorRow: View {
    let icon: String
    let iconColor: Color
    let field: String
    let message: String
    let suggestion: String?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(field)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text(message)
                        .font(.subheadline)
                }

                Spacer()

                if suggestion != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded, let suggestion = suggestion {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .accessibilityHidden(true)
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(iconColor.opacity(0.1))
        )
    }
}

/// Compact badge showing validation status
struct ValidationStatusBadge: View {
    let result: ValidationResult

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .accessibilityHidden(true)

            if !result.isValid {
                Text("\(result.errors.count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
            }

            if !result.warnings.isEmpty {
                Text("\(result.warnings.count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange))
            }
        }
    }

    private var statusIcon: String {
        if !result.isValid {
            return "xmark.circle.fill"
        } else if !result.warnings.isEmpty {
            return "exclamationmark.triangle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        if !result.isValid {
            return .red
        } else if !result.warnings.isEmpty {
            return .orange
        } else {
            return .green
        }
    }
}

/// Field-specific inline error indicator
struct FieldValidationIndicator: View {
    let field: ValidationResult.ConfigField
    let errors: [ValidationResult.ValidationError]
    let warnings: [ValidationResult.ValidationWarning]

    var body: some View {
        let fieldErrors = errors.filter { $0.field == field }
        let fieldWarnings = warnings.filter { $0.field == field }

        if !fieldErrors.isEmpty || !fieldWarnings.isEmpty {
            HStack(spacing: 4) {
                if !fieldErrors.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .accessibilityHidden(true)
                        Text(fieldErrors.first?.message ?? "")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else if !fieldWarnings.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)
                        Text(fieldWarnings.first?.message ?? "")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
}

#Preview("Validation Error Indicator") {
    ValidationErrorIndicator(
        errors: [
            ValidationResult.ValidationError(
                field: .rule("force_cast"),
                message: "Invalid severity value",
                suggestion: "Use 'warning' or 'error'"
            )
        ],
        warnings: [
            ValidationResult.ValidationWarning(
                field: .rule("unknown_rule"),
                message: "Unknown rule identifier",
                suggestion: "Did you mean 'force_cast'?"
            )
        ]
    )
    .padding()
    .frame(width: 400)
}

#Preview("Validation Status Badge - Valid") {
    ValidationStatusBadge(result: .valid)
}

#Preview("Validation Status Badge - Errors") {
    ValidationStatusBadge(
        result: ValidationResult(
            isValid: false,
            errors: [
                ValidationResult.ValidationError(
                    field: .general,
                    message: "Error"
                )
            ],
            warnings: [
                ValidationResult.ValidationWarning(
                    field: .general,
                    message: "Warning"
                )
            ]
        )
    )
}
