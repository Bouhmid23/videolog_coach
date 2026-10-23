import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../utils/ui_utils.dart';

class RoomsScreen extends StatelessWidget {
  const RoomsScreen({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context) {
    const roomName = 'poc-room';

    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        title: Text('Rooms sportives', style: UIUtils.titleMedium(context)),
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
              Text(
                'Choisis ta session',
                style: UIUtils.titleLarge(context).copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              SizedBox(height: UIUtils.xs),
              Text(
                'Les rooms permettent du coaching live + télémétrie.',
                style: UIUtils.bodyMedium(context).copyWith(
                      color: LKColors.textSecondary,
                    ),
              ),
              SizedBox(height: UIUtils.xxl),
              
              // Room Card
              Card(
                color: LKColors.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: UIUtils.borderRadiusAllXL,
                  side: BorderSide(color: LKColors.border, width: 0.5),
                ),
                child: Padding(
                  padding: UIUtils.paddingXL,
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: UIUtils.borderRadiusAllLG,
                          color: LKColors.primary.withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          Icons.videocam_rounded,
                          color: LKColors.primary,
                          size: 32,
                        ),
                      ),
                      SizedBox(width: UIUtils.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              roomName,
                              style: UIUtils.titleMedium(context).copyWith(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            SizedBox(height: UIUtils.xs),
                            Text(
                              'Room de test - simulation athlète',
                              style: UIUtils.bodySmall(context).copyWith(
                                    color: LKColors.textSecondary,
                                  ),
                            ),
                            SizedBox(height: UIUtils.xs),
                            Container(
                              padding: UIUtils.paddingHorizontalSM.add(UIUtils.paddingVerticalXS),
                              decoration: BoxDecoration(
                                color: LKColors.success.withValues(alpha: 0.1),
                                borderRadius: UIUtils.borderRadiusAllSM,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 14,
                                    color: LKColors.success,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Coaching live disponible',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: UIUtils.bodySmall(context).copyWith(
                                            fontSize: 11,
                                            color: LKColors.success,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: UIUtils.md),
                      FilledButton(
                        onPressed: () {
                          context.push('/connect/$roomName', extra: username);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: LKColors.primary,
                          foregroundColor: Colors.white,
                          padding: UIUtils.paddingHorizontalXL.add(UIUtils.paddingVerticalSM),
                          shape: RoundedRectangleBorder(
                            borderRadius: UIUtils.borderRadiusAllMD,
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                            SizedBox(width: UIUtils.xs),
                            Flexible(
                              child: Text(
                                'Rejoindre',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: UIUtils.labelMedium(context).copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
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
              
              // Info Section
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: UIUtils.paddingSM,
                            decoration: BoxDecoration(
                              color: LKColors.secondary.withValues(alpha: 0.1),
                              borderRadius: UIUtils.borderRadiusAllMD,
                            ),
                            child: Icon(
                              Icons.info_outline_rounded,
                              color: LKColors.secondary,
                              size: 20,
                            ),
                          ),
                          SizedBox(width: UIUtils.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'À propos des rooms sportives',
                                  style: UIUtils.labelLarge(context).copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                SizedBox(height: UIUtils.xs),
                                Text(
                                  'Participez à des sessions de coaching en temps réel avec partage vidéo et télémétrie (position GPS, fréquence cardiaque, etc.).',
                                  style: UIUtils.bodySmall(context).copyWith(
                                        color: LKColors.textHint,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
