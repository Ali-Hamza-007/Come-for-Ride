// --- HISTORY SCREEN ---
import 'package:come_for_ride/screen/ride_app.dart';
import 'package:flutter/material.dart';

class HistoryScreen extends StatefulWidget {
  final List<RideHistory> allHistory;
  final VoidCallback onClearAll;
  final Function(int) onDeleteOne;

  const HistoryScreen({
    super.key,
    required this.allHistory,
    required this.onClearAll,
    required this.onDeleteOne,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Ride History",
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.allHistory.isNotEmpty)
            TextButton(
              onPressed: () {
                widget.onClearAll();
                setState(() {}); // Refresh local UI
              },
              child: const Text(
                "Clear All",
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
      body: widget.allHistory.isEmpty
          ? const Center(child: Text("No history found"))
          : ListView.separated(
              itemCount: widget.allHistory.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final item = widget.allHistory[index];
                return Dismissible(
                  // UniqueKey prevents the "Dismissed still in tree" error
                  key: UniqueKey(),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (direction) {
                    widget.onDeleteOne(index);
                  },
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.history),
                    ),
                    title: Text(item.destination),
                    subtitle: Text(item.pickup),
                  ),
                );
              },
            ),
    );
  }
}
