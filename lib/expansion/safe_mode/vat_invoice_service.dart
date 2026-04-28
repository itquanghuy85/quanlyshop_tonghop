import 'expansion_feature_flags.dart';
import 'expansion_module_services.dart';
import 'vat_invoice_repository.dart';

class VatInvoiceService {
  ExpansionFeatureFlags flags;
  final VatModuleService _vatModuleService;
  final VatInvoiceRepository _repository;

  VatInvoiceService({
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
    VatModuleService? vatModuleService,
    VatInvoiceRepository? repository,
  })  : _vatModuleService = vatModuleService ?? VatModuleService(),
        _repository = repository ?? VatInvoiceRepository();

  Future<VatIssuedInvoice> issueAndSaveInvoice({
    required String invoiceNo,
    required VatBuyerInfo buyer,
    required List<VatItemDraft> items,
  }) async {
    _ensureVatEnabled();

    final invoice = _vatModuleService.issueInvoice(
      invoiceNo: invoiceNo,
      buyer: buyer,
      items: items,
    );

    await _repository.saveInvoice(invoice);
    return invoice;
  }

  Future<List<VatIssuedInvoice>> loadInvoices({int limit = 100}) async {
    _ensureVatEnabled();
    return _repository.getInvoices(limit: limit);
  }

  Future<void> close() async {
    await _repository.close();
  }

  void _ensureVatEnabled() {
    if (!flags.enableVAT) {
      throw ModuleDisabledException('VAT');
    }
  }
}
