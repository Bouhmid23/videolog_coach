import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../utils/ui_utils.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context) {
    final kpis = <Map<String, String>>[
      {'label': 'Charge d\'entraînement', 'value': '78%', 'delta': '+6% semaine', 'icon': '💪'},
      {'label': 'Sessions', 'value': '12', 'delta': '4 cette semaine', 'icon': '📅'},
      {'label': 'Cardio moyen', 'value': '162 bpm', 'delta': '-3 bpm', 'icon': '❤️'},
      {'label': 'Score technique', 'value': '91', 'delta': '+4 pts', 'icon': '🎯'},
    ];

    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        title: Text('Tableau de bord', style: UIUtils.titleMedium(context)),
        actions: [
          IconButton(
            onPressed: () {},
            icon: UIUtils.textPrimaryIcon(Icons.notifications_none_rounded, size: 24),
            tooltip: 'Notifications',
          ),
        ],
        elevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: UIUtils.paddingLG,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Card
              Card(
                color: LKColors.surfaceElevated,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: UIUtils.borderRadiusAllXL,
                  side: BorderSide(color: LKColors.border, width: 0.5),
                ),
                child: Container(
                  padding: UIUtils.paddingXL,
                  decoration: BoxDecoration(
                    borderRadius: UIUtils.borderRadiusAllXL,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        LKColors.primary.withValues(alpha: 0.1),
                        LKColors.secondary.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: UIUtils.paddingMD,
                        decoration: BoxDecoration(
                          color: LKColors.primary.withValues(alpha: 0.15),
                          borderRadius: UIUtils.borderRadiusAllFull,
                        ),
                        child: Icon(
                          Icons.directions_run_rounded,
                          size: 32,
                          color: LKColors.primary,
                        ),
                      ),
                      SizedBox(width: UIUtils.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Salut $username 👋',
                              style: UIUtils.titleLarge(context).copyWith(
                                    fontSize: 24,
                                    color: LKColors.textPrimary,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: UIUtils.xs),
                            Text(
                              'Prêt pour ta prochaine session sport aujourd\'hui ?',
                              style: UIUtils.bodyMedium(context).copyWith(
                                    color: LKColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: UIUtils.xxl),
              
              // Section Title
              Text(
                'Indicateurs de performance',
                style: UIUtils.titleMedium(context),
              ),
              SizedBox(height: UIUtils.sm),
              
              // KPIs Grid
              GridView.builder(
                itemCount: kpis.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: UIUtils.md,
                  mainAxisSpacing: UIUtils.md,
                  childAspectRatio: 1.4,
                ),
                itemBuilder: (context, index) {
                  final item = kpis[index];
                  final deltaColor = item['delta']!.startsWith('+') 
                      ? LKColors.success 
                      : item['delta']!.startsWith('-')
                          ? LKColors.warning
                          : LKColors.textSecondary;
                  
                  return Card(
                    color: LKColors.surface,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: UIUtils.borderRadiusAllLG,
                      side: BorderSide(color: LKColors.border, width: 0.5),
                    ),
                    child: Padding(
                      padding: UIUtils.paddingLG,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                item['icon']!,
                                style: const TextStyle(fontSize: 16),
                              ),
                              SizedBox(width: UIUtils.xs),
                              Expanded(
                                child: Text(
                                  item['label']!,
                                  style: UIUtils.bodySmall(context).copyWith(
                                        color: LKColors.textSecondary,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: UIUtils.xs),
                          Text(
                            item['value']!,
                            style: UIUtils.titleSmall(context).copyWith(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          SizedBox(height: UIUtils.xs),
                          Row(
                            children: [
                              Icon(
                                item['delta']!.startsWith('+') 
                                    ? Icons.arrow_upward_rounded 
                                    : Icons.arrow_downward_rounded,
                                size: 12,
                                color: deltaColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item['delta']!,
                                style: UIUtils.bodySmall(context).copyWith(
                                      color: deltaColor,
                                      fontSize: 10,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: UIUtils.xxl),
              
              // Next Session Card
              Card(
                color: LKColors.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: UIUtils.borderRadiusAllLG,
                  side: BorderSide(color: LKColors.border, width: 0.5),
                ),
                child: Padding(
                  padding: UIUtils.paddingLG,
                  child: Row(
                    children: [
                      Container(
                        padding: UIUtils.paddingSM,
                        decoration: BoxDecoration(
                          color: LKColors.secondary.withValues(alpha: 0.1),
                          borderRadius: UIUtils.borderRadiusAllMD,
                        ),
                        child: Icon(
                          Icons.event_available_rounded,
                          color: LKColors.secondary,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: UIUtils.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Prochaine séance',
                              style: UIUtils.labelMedium(context).copyWith(
                                    color: LKColors.textSecondary,
                                  ),
                            ),
                            Text(
                              'Coaching Room',
                              style: UIUtils.titleSmall(context).copyWith(
                                    fontSize: 16,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                       SizedBox(width:UIUtils.md),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '18:30',
                            style: UIUtils.titleSmall(context).copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            'Aujourd\'hui',
                            style: UIUtils.bodySmall(context).copyWith(
                                  color: LKColors.textHint,
                                ),
                          ),
                        ],
                      ),
                      SizedBox(width: UIUtils.md),
                      FilledButton.tonal(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          backgroundColor: LKColors.primary.withValues(alpha: 0.1),
                          foregroundColor: LKColors.primary,
                          padding: UIUtils.paddingHorizontalMD.add(UIUtils.paddingVerticalSM),
                          shape: RoundedRectangleBorder(
                            borderRadius: UIUtils.borderRadiusAllSM,
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        child: Text('Détails', style: UIUtils.bodySmall(context).copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: UIUtils.xxl),
              
              // Action Button
              FilledButton.icon(
                onPressed: () => context.push('/rooms/$username'),
                icon: Icon(Icons.sports_score_rounded, size: 20),
                label: Text(
                  'Entrer dans une room',
                  style: UIUtils.labelLarge(context).copyWith(color: Colors.white),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: LKColors.primary,
                  foregroundColor: Colors.white,
                  padding: UIUtils.paddingVerticalLG.add(UIUtils.paddingHorizontalXXL),
                  shape: RoundedRectangleBorder(borderRadius: UIUtils.borderRadiusAllMD),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
