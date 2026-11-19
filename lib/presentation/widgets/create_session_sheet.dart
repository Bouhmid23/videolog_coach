import 'package:flutter/material.dart';

import '../../core/api_service.dart';
import '../../data/account_models.dart';
import '../../data/session_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

Future<OrgSession?> showCreateSessionSheet(
  BuildContext context, {
  required String orgId,
}) {
  return showModalBottomSheet<OrgSession>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => CreateSessionSheet(orgId: orgId),
  );
}

class CreateSessionSheet extends StatefulWidget {
  const CreateSessionSheet({required this.orgId, super.key});

  final String orgId;

  @override
  State<CreateSessionSheet> createState() => _CreateSessionSheetState();
}

class _CreateSessionSheetState extends State<CreateSessionSheet> {
  final _titleCtrl = TextEditingController();
  List<OrgGroup> _groups = const [];
  List<OrgMemberSummary> _members = const [];
  String? _selectedGroupId;
  final Set<String> _selectedParticipantUids = {};
  bool _loadingMeta = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    try {
      final results = await Future.wait([
        ApiService.instance.fetchOrgGroups(widget.orgId),
        ApiService.instance.fetchOrgMembers(widget.orgId),
      ]);
      if (!mounted) return;
      setState(() {
        _groups = results[0] as List<OrgGroup>;
        _members = results[1] as List<OrgMemberSummary>;
        _loadingMeta = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMeta = false);
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.length < 2) {
      setState(
        () => _error = 'Le titre de la séance doit contenir au moins 2 caractères.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final created = await ApiService.instance.createOrgSession(
        widget.orgId,
        title: title,
        groupId: _selectedGroupId,
        participantUids: _selectedParticipantUids.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de créer la séance.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(top: 64, bottom: bottomInset),
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: LKColors.border, width: 0.6),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: UIUtils.paddingXL,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: LKColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              SizedBox(height: UIUtils.lg),
              Row(
                children: [
                  const Icon(
                    Icons.add_circle_outline_rounded,
                    color: LKColors.primary,
                  ),
                  SizedBox(width: UIUtils.sm),
                  Expanded(
                    child: Text(
                      'Nouvelle séance',
                      style: UIUtils.titleMedium(context),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              SizedBox(height: UIUtils.md),

              TextField(
                controller: _titleCtrl,
                decoration: UIUtils.inputDecoration(
                  labelText: 'Titre de la séance *',
                  hintText: 'Ex: Fractionné seuil — Groupe A',
                  prefixIcon: Icons.title_rounded,
                ),
              ),
              SizedBox(height: UIUtils.md),

              if (_loadingMeta)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_groups.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedGroupId,
                    dropdownColor: LKColors.surfaceElevated,
                    decoration: UIUtils.inputDecoration(
                      labelText: 'Groupe (optionnel)',
                      prefixIcon: Icons.groups_rounded,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Aucun groupe spécifique'),
                      ),
                      ..._groups.map(
                        (g) => DropdownMenuItem<String?>(
                          value: g.id,
                          child: Text('${g.name} (${g.sport})'),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedGroupId = value;
                      });
                    },
                  ),
                  SizedBox(height: UIUtils.md),
                ],

                if (_members.isNotEmpty) ...[
                  Text(
                    'Participants (${_selectedParticipantUids.length} sélectionné${_selectedParticipantUids.length > 1 ? 's' : ''})',
                    style: UIUtils.labelLarge(context),
                  ),
                  SizedBox(height: UIUtils.xs),
                  Text(
                    _selectedGroupId != null && _selectedParticipantUids.isEmpty
                        ? 'Sans sélection individuelle, tous les membres du groupe seront invités.'
                        : 'Sélectionnez les athlètes/coachs participant à la séance.',
                    style: UIUtils.bodySmall(context),
                  ),
                  SizedBox(height: UIUtils.sm),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: LKColors.surface,
                      borderRadius: UIUtils.borderRadiusAllMD,
                      border: Border.all(color: LKColors.border, width: 0.6),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _members.length,
                        itemBuilder: (context, index) {
                          final member = _members[index];
                          final checked =
                              _selectedParticipantUids.contains(member.uid);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            title: Text(
                              member.displayName,
                              style: UIUtils.bodyMedium(context).copyWith(
                                color: LKColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              member.role,
                              style: UIUtils.bodySmall(context),
                            ),
                            onChanged: (on) {
                              setState(() {
                                if (on == true) {
                                  _selectedParticipantUids.add(member.uid);
                                } else {
                                  _selectedParticipantUids.remove(member.uid);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],

              if (_error != null) ...[
                SizedBox(height: UIUtils.md),
                Text(
                  _error!,
                  style: UIUtils.bodySmall(
                    context,
                  ).copyWith(color: LKColors.danger),
                ),
              ],
              SizedBox(height: UIUtils.lg),

              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_submitting ? 'Création…' : 'Créer la séance'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
