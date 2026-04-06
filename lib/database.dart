import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:intl/intl.dart';
import 'package:nrf/ble_data_model.dart';
import 'package:nrf/database_helper.dart';
import 'package:nrf/ui_constants.dart';

class DatabaseScreen extends StatefulWidget {
  final DiscoveredDevice? device;

  const DatabaseScreen({super.key, required this.device});

  @override
  DatabaseScreenState createState() => DatabaseScreenState();
}

class DatabaseScreenState extends State<DatabaseScreen> {
  List<BleData> _allData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    refreshData();
  }

  Future<void> refreshData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await DatabaseHelper().getBleData(limit: 500);
      if (mounted) {
        setState(() {
          _allData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading DB data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: refreshData,
                color: kAccentColor,
                child: _allData.isEmpty
                    ? const Center(child: Text('No data found in database'))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(top: kScreenTopPadding),
                        scrollDirection: Axis.vertical,
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildDataTable(),
                        ),
                      ),
              ),
      ),
    );
  }

  Widget _buildDataTable() {
    return DataTable(
      columnSpacing: 18,
      horizontalMargin: 12,
      headingRowHeight: 56,
      dataRowMaxHeight: 64,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFFBFBFB)),
      dividerThickness: 0.5,
      showCheckboxColumn: false,
      headingTextStyle: TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade500,
        fontSize: 12,
        letterSpacing: 0.2,
      ),
      columns: const [
        DataColumn(label: Text('시간')),
        DataColumn(label: Text('HEART RATE')),
        DataColumn(label: Text('SPO2')),
        DataColumn(label: Text('RR')),
        DataColumn(label: Text('SDNN')),
        DataColumn(label: Text('RMSSD')),
        DataColumn(label: Text('스트레스')),
        DataColumn(label: Text('수면')),
      ],
      rows: _allData.map((data) {
        final timeStr = DateFormat('MMdd HH:mm:ss').format(data.timestamp);
        
        return DataRow(cells: [
          // 시간
          DataCell(Text(timeStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          
          // HEART RATE
          DataCell(_buildValueCell(data.hr.toString(), 'bpm')),
          
          // SPO2
          DataCell(_buildValueCell(data.spo2.toString(), '%')),
          
          // RR
          DataCell(_buildValueCell(data.rr.toString(), 'ms')),
          
          // SDNN
          DataCell(_buildValueCell(data.sdnn.toString(), 'ms')),
          
          // RMSSD
          DataCell(_buildValueCell(data.rmssd.toString(), 'ms')),

          // 스트레스
          DataCell(_buildValueCell(data.stress.toString(), '/100', 
              valueColor: data.stress > 70 ? Colors.red : (data.stress > 40 ? Colors.orange : Colors.green))),
          
          // 수면 (Mock)
          DataCell(Text(_sleepLabel(data.sleep), style: TextStyle(color: Colors.grey.shade400))),
        ]);
      }).toList(),
    );
  }

  String _sleepLabel(BleSleepType sleep) {
    return switch (sleep) {
      BleSleepType.none => '없음',
      BleSleepType.awake => '비수면',
      BleSleepType.light => '얕은 수면',
      BleSleepType.deep => '깊은 수면',
      BleSleepType.rem => 'REM',
      BleSleepType.unknown => '-',
    };
  }

  Widget _buildValueCell(String value, String unit, {Color? valueColor}) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor ?? Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const WidgetSpan(child: SizedBox(width: 2)),
          TextSpan(
            text: unit,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 10,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
