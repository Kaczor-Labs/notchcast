package enum IslandStoreCall<Content> {
    case start(ActivityOptions<Content>)
    case update(String, ActivityUpdate<Content>)
    case end(String)
    case expand(String?)
    case collapse
}
