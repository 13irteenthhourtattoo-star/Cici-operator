import 'dart:convert';
import 'dart:developer' as developer;

import '../models/agent_manifest.dart';
import '../models/assistant_action.dart';
import '../models/discovered_app.dart';
import 'app_discovery_service.dart';

class CapabilityRegistry {
  final List<AssistantAction> _actions = [];
  final AppDiscoveryService _appDiscoveryService = AppDiscoveryService();

  List<AssistantAction> get actions => List.unmodifiable(_actions);
  bool get hasAvailableActions => _actions.isNotEmpty;
  int get availableActionCount => _actions.length;

  Future<void> initialize() async {
    _actions.clear();
    _actions.add(
      const AssistantAction(
        sourceType: AssistantActionSourceType.oacp,
        sourceId: 'cici.operator',
        actionId: 'open_chatgpt',
        displayName: 'Open ChatGPT',
        description: 'Open the ChatGPT app',
        confirmationMessage: 'Opening ChatGPT',
        domain: 'apps',
        appDomains: ['assistant', 'chat'],
        appKeywords: ['chatgpt', 'cici', 'openai'],
        appAliases: ['ChatGPT', 'Cici'],
        aliases: ['open chatgpt', 'launch chatgpt', 'start chatgpt'],
        examples: [
          'Open ChatGPT',
          'Launch ChatGPT',
          'Start ChatGPT',
        ],
        keywords: ['open', 'launch', 'chatgpt', 'cici'],
        disambiguationHints: [],
        dispatchType: AssistantActionDispatchType.activity,
        androidAction: 'android.intent.action.MAIN',
        packageName: 'com.openai.chatgpt',
        extrasMapping: {},
        parameters: [],
      ),
    );
    _actions.add(
      const AssistantAction(
        sourceType: AssistantActionSourceType.oacp,
        sourceId: 'cici.operator',
        actionId: 'send_to_cici',
        displayName: 'Send to Cici',
        description:
            'Send a spoken conversational message to Cici in ChatGPT.',
        confirmationMessage: 'Sending to Cici',
        domain: 'chat',
        appDomains: ['assistant', 'chat'],
        appKeywords: ['cici', 'chatgpt', 'message'],
        appAliases: ['Cici', 'ChatGPT'],
        aliases: [
          'tell cici',
          'ask cici',
          'message cici',
          'send message to cici',
          'send message to chatgpt',
        ],
        examples: [
          'Tell Cici banana',
          'Ask Cici what time it is',
          'Send message to ChatGPT hello',
        ],
        keywords: ['tell cici', 'ask cici', 'message cici', 'send message'],
        disambiguationHints: [
          'Use this when the user wants to say or send something to Cici, not merely open ChatGPT.',
        ],
        dispatchType: AssistantActionDispatchType.broadcast,
        androidAction: 'com.cicibridge.SEND_TO_CICI',
        packageName: 'com.cicibridge',
        extrasMapping: {},
        parameters: [
          AssistantActionParameter(
            name: 'message',
            type: 'string',
            required: true,
            description: 'The exact conversational message to send to Cici.',
            extractionHint:
                'Extract only what the user wants Cici to receive. For "Tell Cici banana", return "banana".',
            examples: ['banana', 'what time is it', 'hello'],
          ),
        ],
      ),
    );

    final discoveredApps = await _safeDiscoverApps();

    for (final discoveredApp in discoveredApps) {
      if (!discoveredApp.hasCompleteMetadata) {
        developer.log(
          'Skipping OACP provider ${discoveredApp.authority}: ${discoveredApp.error ?? 'missing metadata'}',
          name: 'CapabilityRegistry',
        );
        continue;
      }

      try {
        final appJson =
            jsonDecode(discoveredApp.manifestJson!) as Map<String, dynamic>;
        final manifest = AgentManifest.fromJson(appJson);
        if (manifest.appId != discoveredApp.packageName) {
          developer.log(
            'Manifest appId ${manifest.appId} does not match provider package ${discoveredApp.packageName}',
            name: 'CapabilityRegistry',
          );
          continue;
        }

        _actions.addAll(_buildOacpActions(manifest));
      } catch (e) {
        developer.log(
          'Failed to load discovered manifest from ${discoveredApp.authority}',
          name: 'CapabilityRegistry',
          error: e,
        );
      }
    }
  }

  Future<List<DiscoveredApp>> _safeDiscoverApps() async {
    try {
      return await _appDiscoveryService.discoverApps();
    } catch (e) {
      developer.log(
        'OACP app discovery failed.',
        name: 'CapabilityRegistry',
        error: e,
      );
      return const [];
    }
  }

  String allActionsAsJson() {
    return jsonEncode(
      _actions.map((action) => action.toJson()).toList(growable: false),
    );
  }

  AssistantAction? findAction(
    String sourceType,
    String sourceId,
    String actionId,
  ) {
    for (final action in _actions) {
      if (action.sourceType.name == sourceType &&
          action.sourceId == sourceId &&
          action.actionId == actionId) {
        return action;
      }
    }
    return null;
  }

  List<AssistantAction> _buildOacpActions(AgentManifest manifest) {
    return manifest.capabilities
        .map((capability) {
          final extrasMapping =
              capability.invoke.android.extrasMapping ??
              <String, String>{
                for (final parameter in capability.parameters)
                  parameter.name: parameter.name,
              };

          final dispatchType = switch (capability.invoke.android.type) {
            'activity' => AssistantActionDispatchType.activity,
            'broadcast' || 'intent' => AssistantActionDispatchType.broadcast,
            _ => AssistantActionDispatchType.broadcast,
          };

          return AssistantAction(
            sourceType: AssistantActionSourceType.oacp,
            sourceId: manifest.appId,
            actionId: capability.id,
            displayName: manifest.displayName,
            description: capability.description,
            confirmationMessage:
                capability.executionMessage ?? capability.description,
            confirmationPrompt: capability.confirmationMessage,
            domain: capability.domain,
            appDomains: manifest.appDomains,
            appKeywords: manifest.appKeywords,
            appAliases: manifest.appAliases,
            aliases: capability.aliases,
            examples: capability.examples,
            keywords: capability.keywords,
            disambiguationHints: capability.disambiguationHints,
            dispatchType: dispatchType,
            androidAction: capability.invoke.android.action,
            packageName: manifest.appId,
            extrasMapping: extrasMapping,
            parameters: capability.parameters
                .map(
                  (parameter) => AssistantActionParameter(
                    name: parameter.name,
                    type: parameter.type,
                    required: parameter.required,
                    description: parameter.description ?? parameter.prompt,
                    extractionHint: parameter.extractionHint,
                    examples: parameter.examples,
                    aliases: parameter.aliases,
                    enumValues: parameter.enumValues,
                    defaultValue: parameter.defaultValue,
                    minimum: parameter.minimum,
                    maximum: parameter.maximum,
                    pattern: parameter.pattern,
                    entityType: parameter.entityRef?.entityType,
                    entityResolution: parameter.entityRef?.resolution,
                    entityDisambiguationPrompt:
                        parameter.entityRef?.entityDisambiguationPrompt,
                    entitySnapshot: parameter.entitySnapshot
                        .map((entity) => entity.toJson())
                        .toList(growable: false),
                  ),
                )
                .toList(growable: false),
            completionMode: capability.completionMode,
            resultTransportType: capability.resultTransport?.android.type,
            resultTransportAction: capability.resultTransport?.android.action,
            errorCodes: capability.errorCodes,
            supportsCancellation: capability.supportsCancellation,
            cancelCapabilityId: capability.cancelCapabilityId,
          );
        })
        .toList(growable: false);
  }
}
