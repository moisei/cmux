import Foundation

// A Chief DM the owner no longer has (cx-ebm.55). The durable cache is keyed
// by the owner's session name, which a Chief home made again at the same path
// keeps, so the cache can seed the old home's Chief conversation. A send the
// user made to it before the owner answered must reach the live Chief, never
// vanish with the old conversation. So reconnect resends wait until the
// owner's inbox says which conversations exist, and the text sends of a
// vanished Chief DM move to the live DM with the same Chief.
extension HomeStore {
    /// Reconnect resends go now, or after the inbox when the mirror's inbox
    /// is stale (seeded from the cache, or a refetch failed).
    func resendAfterReconnect() {
        if mirror.isStale(.inbox) {
            resendsAwaitInbox = true
        } else {
            enqueueResends(log.takeResends())
        }
    }

    /// After an inbox replaced `previous`: the vanished Chief DMs' sends move
    /// to the live one, then the resends held for the inbox go.
    func afterInbox(previous: [ConversationID: ConversationSummary]) {
        for (id, old) in previous where mirror.conversations[id] == nil {
            guard let chief = Self.chiefOfDM(old, me: me?.id),
                  let live = mirror.conversations.values
                      .filter({ Self.chiefOfDM($0, me: me?.id) == chief })
                      .min(by: { ($0.createdAt, $0.id.rawValue) < ($1.createdAt, $1.id.rawValue) }) else { continue }
            let moved = log.moveSends(from: id, to: live.id)
            guard !moved.isEmpty else { continue }
            removeFromSendQueue(id) { moved.contains($0) }
            for key in moved { enqueueSend(key, in: live.id) }
            bumpTranscript(live.id)
        }
        if resendsAwaitInbox, isOnline {
            resendsAwaitInbox = false
            enqueueResends(log.takeResends())
        }
    }

    /// The Chief of a DM between `me` and one Chief, else nil.
    static func chiefOfDM(_ summary: ConversationSummary, me: ParticipantID?) -> ParticipantID? {
        let chiefs = summary.participants.filter(\.isChief)
        let others = summary.participants.filter { !$0.isChief && $0.id != me }
        guard chiefs.count == 1, others.isEmpty else { return nil }
        return chiefs[0].id
    }
}
