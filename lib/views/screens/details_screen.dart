import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:group_money_management_app/utils/members.dart';
import 'package:intl/intl.dart';

class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});

  Stream<List<PaymentData>> get paymentsStream {
    return FirebaseFirestore.instance
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            final paidTs = data['paidAt'] as Timestamp?;
            final createdTs = data['createdAt'] as Timestamp?;
            final date =
                paidTs?.toDate() ?? createdTs?.toDate() ?? DateTime.now();

            return PaymentData(
              id: doc.id,
              amount: (data['amount'] as num?)?.toDouble() ?? 0,
              description: data['description'] as String? ?? 'No description',
              payer: data['payer'] as String? ?? '',
              splits: (data['splits'] as List?)?.cast<String>() ?? [],
              paidAt: date,
            );
          }).toList();
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Payments',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        actions: [
          StreamBuilder<List<PaymentData>>(
            stream: paymentsStream,
            builder: (context, snapshot) {
              return IconButton(
                icon: const Icon(Icons.summarize),
                onPressed: snapshot.hasData
                    ? () => _showOverallSummary(context, snapshot.data!)
                    : null,
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<PaymentData>>(
        stream: paymentsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No payments yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          final payments = snapshot.data!;
          final monthlyPayments = _groupByMonth(payments);
          final sortedMonths = monthlyPayments.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedMonths.length,
            itemBuilder: (context, index) {
              final monthKey = sortedMonths[index];
              final monthPayments = monthlyPayments[monthKey]!;
              final monthName = DateFormat(
                'MMMM yyyy',
              ).format(monthPayments.first.paidAt);
              final monthTotal = monthPayments.fold(
                0.0,
                (sum, p) => sum + p.amount,
              );

              return _MonthCard(
                monthName: monthName,
                paymentCount: monthPayments.length,
                total: monthTotal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MonthlyDetailsScreen(
                      monthName: monthName,
                      monthKey: monthKey,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Map<String, List<PaymentData>> _groupByMonth(List<PaymentData> payments) {
    final Map<String, List<PaymentData>> grouped = {};
    for (final payment in payments) {
      final key = DateFormat('yyyy-MM').format(payment.paidAt);
      grouped.putIfAbsent(key, () => []).add(payment);
    }
    return grouped;
  }

  void _showOverallSummary(BuildContext context, List<PaymentData> payments) {
    final summary = _calculateSummary(payments);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Overall Summary'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryCard(
                title: 'Total Spent',
                value: '₹${summary.total.toStringAsFixed(2)}',
                color: Colors.blue,
              ),
              const SizedBox(height: 16),
              const Text(
                'Per Person',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...members.map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(m),
                      Text(
                        '₹${summary.spent[m]!.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              const Text(
                'Settlements',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (summary.settlements.isEmpty)
                const Text(
                  'All settled!',
                  style: TextStyle(color: Colors.green),
                )
              else
                ...summary.settlements.map(
                  (s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(s, style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  SummaryData _calculateSummary(List<PaymentData> payments) {
    double total = 0;
    final spent = {for (final m in members) m: 0.0};
    final net = {for (final m in members) m: 0.0};

    for (final payment in payments) {
      if (payment.amount <= 0 || payment.splits.isEmpty) continue;
      total += payment.amount;
      spent[payment.payer] = (spent[payment.payer] ?? 0) + payment.amount;
      final share = payment.amount / payment.splits.length;
      for (final m in payment.splits) {
        net[m] = (net[m] ?? 0) - share;
      }
      net[payment.payer] = (net[payment.payer] ?? 0) + payment.amount;
    }

    final settlements = _calculateSettlements(net);
    return SummaryData(total: total, spent: spent, settlements: settlements);
  }

  List<String> _calculateSettlements(Map<String, double> net) {
    final creditors =
        net.entries
            .where((e) => e.value > 0.01)
            .map((e) => _Party(e.key, e.value))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
    final debtors =
        net.entries
            .where((e) => e.value < -0.01)
            .map((e) => _Party(e.key, -e.value))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    final settlements = <String>[];
    int i = 0, j = 0;

    while (i < debtors.length && j < creditors.length) {
      final amt = debtors[i].amount < creditors[j].amount
          ? debtors[i].amount
          : creditors[j].amount;
      if (amt > 0.01) {
        settlements.add(
          '${debtors[i].name} → ${creditors[j].name} = ₹${amt.toStringAsFixed(2)}',
        );
      }
      debtors[i].amount -= amt;
      creditors[j].amount -= amt;
      if (debtors[i].amount <= 0.01) i++;
      if (creditors[j].amount <= 0.01) j++;
    }
    return settlements;
  }
}

class PaymentData {
  final String id;
  final double amount;
  final String description;
  final String payer;
  final List<String> splits;
  final DateTime paidAt;

  PaymentData({
    required this.id,
    required this.amount,
    required this.description,
    required this.payer,
    required this.splits,
    required this.paidAt,
  });
}

class SummaryData {
  final double total;
  final Map<String, double> spent;
  final List<String> settlements;

  SummaryData({
    required this.total,
    required this.spent,
    required this.settlements,
  });
}

class _Party {
  final String name;
  double amount;
  _Party(this.name, this.amount);
}

/// Accumulates total amount, payment count, per-payer amounts, and individual payments
/// for a unique split-member combination.
class _SplitGroupData {
  final List<String> members;
  double total = 0;
  int paymentCount = 0;

  /// How much each member paid as the payer within this split group.
  final Map<String, double> paidByMember = {};

  /// The actual payments in this split combination.
  final List<PaymentData> payments = [];

  _SplitGroupData({required this.members}) {
    for (final m in members) {
      paidByMember[m] = 0.0;
    }
  }

  int get memberCount => members.length;

  void addPayment(PaymentData payment) {
    total += payment.amount;
    paymentCount++;
    paidByMember[payment.payer] =
        (paidByMember[payment.payer] ?? 0) + payment.amount;
    payments.add(payment);
  }
}

class _MonthCard extends StatelessWidget {
  final String monthName;
  final int paymentCount;
  final double total;
  final VoidCallback onTap;

  const _MonthCard({
    required this.monthName,
    required this.paymentCount,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.calendar_month,
                    color: Colors.blue.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        monthName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$paymentCount payment${paymentCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.green,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, color: color.withOpacity(0.7)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class MonthlyDetailsScreen extends StatefulWidget {
  final String monthName;
  final String monthKey;

  const MonthlyDetailsScreen({
    super.key,
    required this.monthName,
    required this.monthKey,
  });

  @override
  State<MonthlyDetailsScreen> createState() => _MonthlyDetailsScreenState();
}

class _MonthlyDetailsScreenState extends State<MonthlyDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedTab = 'All';

  Stream<List<PaymentData>> get monthPaymentsStream {
    return FirebaseFirestore.instance
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final allPayments = snapshot.docs.map((doc) {
            final data = doc.data();
            final paidTs = data['paidAt'] as Timestamp?;
            final createdTs = data['createdAt'] as Timestamp?;
            final date =
                paidTs?.toDate() ?? createdTs?.toDate() ?? DateTime.now();

            return PaymentData(
              id: doc.id,
              amount: (data['amount'] as num?)?.toDouble() ?? 0,
              description: data['description'] as String? ?? 'No description',
              payer: data['payer'] as String? ?? '',
              splits: (data['splits'] as List?)?.cast<String>() ?? [],
              paidAt: date,
            );
          }).toList();

          return allPayments.where((payment) {
            final paymentMonthKey = DateFormat(
              'yyyy-MM',
            ).format(payment.paidAt);
            return paymentMonthKey == widget.monthKey;
          }).toList()..sort((a, b) => b.paidAt.compareTo(a.paidAt));
        });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: members.length + 1, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTab = _tabController.index == 0
            ? 'All'
            : members[_tabController.index - 1];
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PaymentData>>(
      stream: monthPaymentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.grey.shade50,
            appBar: AppBar(
              title: Text(
                widget.monthName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.grey.shade50,
            appBar: AppBar(title: Text(widget.monthName)),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final payments = snapshot.data ?? [];

        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            title: Text(
              widget.monthName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.summarize),
                onPressed: payments.isNotEmpty
                    ? () => _showMonthSummary(payments)
                    : null,
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: Theme.of(context).primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Theme.of(context).primaryColor,
                  tabs: [
                    const Tab(text: 'All'),
                    ...members.map(
                      (m) => Tab(text: m.length > 8 ? m.substring(0, 8) : m),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: payments.isEmpty
              ? Center(
                  child: Text(
                    'No payments this month',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : Column(
                  children: [
                    _buildSummaryCard(payments),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPaymentsList(payments, null),
                          ...members.map(
                            (m) => _buildPaymentsList(payments, m),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSummaryCard(List<PaymentData> payments) {
    final total = payments.fold(0.0, (sum, p) => sum + p.amount);
    double personAmount = 0;
    if (_selectedTab != 'All') {
      personAmount = payments
          .where((p) => p.payer == _selectedTab)
          .fold(0.0, (sum, p) => sum + p.amount);
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _selectedTab == 'All'
          ? Column(
              children: [
                const Text(
                  'Total Spent',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${payments.length} payments',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            )
          : Column(
              children: [
                Text(
                  '$_selectedTab\'s Payments',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  personAmount > 0
                      ? '₹${personAmount.toStringAsFixed(2)} paid'
                      : 'No payments this month',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPaymentsList(List<PaymentData> allPayments, String? person) {
    final filtered = person == null
        ? allPayments
        : allPayments.where((p) => p.payer == person).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          person == null ? 'No payments' : 'No payments this month',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final payment = filtered[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            onTap: () => _showPaymentDetails(context, payment),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.payment, color: Colors.green, size: 20),
            ),
            title: Text(
              payment.description,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('MMM dd, yyyy').format(payment.paidAt)} • ${payment.payer} paid',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${payment.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.green,
                      ),
                    ),
                    Text(
                      'Paid',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(context, payment),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deletePayment(BuildContext context, PaymentData payment) async {
    try {
      await FirebaseFirestore.instance
          .collection('payments')
          .doc(payment.id)
          .delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment deleted successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, PaymentData payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Payment'),
        content: Text(
          'Delete "${payment.description}"?\n\nAmount: ₹${payment.amount.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePayment(context, payment);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showPaymentDetails(BuildContext context, PaymentData payment) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmDelete(context, payment);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              payment.description,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Amount: ₹${payment.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Paid by: ${payment.payer}',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              'Paid at: ${DateFormat('MMM d, yyyy • h:mm a').format(payment.paidAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            if (payment.splits.isNotEmpty) ...[
              const Text(
                'Split between',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: payment.splits
                    .map(
                      (s) => Chip(
                        label: Text(s),
                        backgroundColor: Colors.blue.shade50,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Text(
                'Each owes: ₹${(payment.amount / payment.splits.length).toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else
              Text(
                'No splits recorded',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }

  /// Returns a canonical key for a list of split members (sorted, joined).
  String _splitKey(List<String> splits) {
    final sorted = List<String>.from(splits)..sort();
    return sorted.join(' & ');
  }

  /// Groups payments by their unique split-member combination.
  Map<String, _SplitGroupData> _groupBySplitCombo(List<PaymentData> payments) {
    final Map<String, _SplitGroupData> groups = {};
    for (final p in payments) {
      if (p.splits.isEmpty) continue;
      final key = _splitKey(p.splits);
      if (!groups.containsKey(key)) {
        final sorted = List<String>.from(p.splits)..sort();
        groups[key] = _SplitGroupData(members: sorted);
      }
      groups[key]!.addPayment(p);
    }
    return groups;
  }

  void _showMonthSummary(List<PaymentData> payments) {
    final summary = DetailsScreen()._calculateSummary(payments);
    final splitGroups = _groupBySplitCombo(payments);
    // Sort groups by total descending
    final sortedGroups = splitGroups.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.monthName} Summary'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryCard(
                title: 'Total Spent',
                value: '₹${summary.total.toStringAsFixed(2)}',
                color: Colors.blue,
              ),
              const SizedBox(height: 16),
              const Text(
                'Per Person',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...members.map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(m),
                      Text(
                        '₹${summary.spent[m]!.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Split Groups ────────────────────────────────────────────
              if (sortedGroups.isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'Split Groups',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ...sortedGroups.map((entry) {
                  final group = entry.value;
                  final perPerson = group.memberCount > 0
                      ? group.total / group.memberCount
                      : 0.0;
                  return Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        expandedAlignment: Alignment.topLeft,
                        title: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: group.members.map((m) {
                            final paid = group.paidByMember[m] ?? 0.0;
                            final hasPaid = paid > 0.01;
                            return Chip(
                              label: Text(
                                '$m  ₹${paid.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: hasPaid
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: hasPaid
                                      ? Colors.indigo.shade800
                                      : Colors.grey.shade600,
                                ),
                              ),
                              backgroundColor: hasPaid
                                  ? Colors.indigo.shade100
                                  : Colors.grey.shade100,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            );
                          }).toList(),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${group.paymentCount} payment${group.paymentCount == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  'Total  ₹${group.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Each owes: ₹${perPerson.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        children: [
                          const Divider(height: 16),
                          ...group.payments.map((p) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${p.description} (${p.payer})',
                                      style: const TextStyle(fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '₹${p.amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              // ────────────────────────────────────────────────────────────
              const Divider(height: 24),
              const Text(
                'Settlements',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (summary.settlements.isEmpty)
                const Text(
                  'All settled!',
                  style: TextStyle(color: Colors.green),
                )
              else
                ...summary.settlements.map(
                  (s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(s, style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
