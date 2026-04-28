import 'expansion_module_services.dart';

class VatInvoiceRow {
  final String invoiceNo;
  final String companyName;
  final String taxCode;
  final String address;
  final String email;
  final double subTotal;
  final double totalTax;
  final double grandTotal;
  final DateTime issuedAt;
  final bool locked;

  const VatInvoiceRow({
    required this.invoiceNo,
    required this.companyName,
    required this.taxCode,
    required this.address,
    required this.email,
    required this.subTotal,
    required this.totalTax,
    required this.grandTotal,
    required this.issuedAt,
    required this.locked,
  });

  factory VatInvoiceRow.fromIssued(VatIssuedInvoice invoice) {
    return VatInvoiceRow(
      invoiceNo: invoice.invoiceNo,
      companyName: invoice.buyer.companyName,
      taxCode: invoice.buyer.taxCode,
      address: invoice.buyer.address,
      email: invoice.buyer.email,
      subTotal: invoice.subTotal,
      totalTax: invoice.totalTax,
      grandTotal: invoice.grandTotal,
      issuedAt: invoice.issuedAt,
      locked: invoice.locked,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceNo': invoiceNo,
      'companyName': companyName,
      'taxCode': taxCode,
      'address': address,
      'email': email,
      'subTotal': subTotal,
      'totalTax': totalTax,
      'grandTotal': grandTotal,
      'issuedAt': issuedAt.millisecondsSinceEpoch,
      'locked': locked ? 1 : 0,
    };
  }

  static VatInvoiceRow fromMap(Map<String, dynamic> map) {
    return VatInvoiceRow(
      invoiceNo: (map['invoiceNo'] ?? '').toString(),
      companyName: (map['companyName'] ?? '').toString(),
      taxCode: (map['taxCode'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      subTotal: (map['subTotal'] as num?)?.toDouble() ?? 0,
      totalTax: (map['totalTax'] as num?)?.toDouble() ?? 0,
      grandTotal: (map['grandTotal'] as num?)?.toDouble() ?? 0,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['issuedAt'] as num?)?.toInt() ?? 0,
      ),
      locked: (map['locked'] as num?)?.toInt() == 1,
    );
  }

  VatBuyerInfo toBuyerInfo() {
    return VatBuyerInfo(
      companyName: companyName,
      taxCode: taxCode,
      address: address,
      email: email,
    );
  }
}

class VatInvoiceItemRow {
  final String invoiceNo;
  final String productName;
  final int quantity;
  final double unitPrice;
  final int taxPercent;
  final double subTotal;
  final double taxAmount;

  const VatInvoiceItemRow({
    required this.invoiceNo,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.taxPercent,
    required this.subTotal,
    required this.taxAmount,
  });

  factory VatInvoiceItemRow.fromDraft(String invoiceNo, VatItemDraft item) {
    return VatInvoiceItemRow(
      invoiceNo: invoiceNo,
      productName: item.productName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      taxPercent: item.taxPercent,
      subTotal: item.subTotal,
      taxAmount: item.taxAmount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceNo': invoiceNo,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'taxPercent': taxPercent,
      'subTotal': subTotal,
      'taxAmount': taxAmount,
    };
  }

  static VatInvoiceItemRow fromMap(Map<String, dynamic> map) {
    return VatInvoiceItemRow(
      invoiceNo: (map['invoiceNo'] ?? '').toString(),
      productName: (map['productName'] ?? '').toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
      taxPercent: (map['taxPercent'] as num?)?.toInt() ?? 0,
      subTotal: (map['subTotal'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['taxAmount'] as num?)?.toDouble() ?? 0,
    );
  }

  VatItemDraft toDraft() {
    return VatItemDraft(
      productName: productName,
      quantity: quantity,
      unitPrice: unitPrice,
      taxPercent: taxPercent,
    );
  }
}
