extension GraphQLEndpoint {
    /// `/v1/audience/<id>/staffql`, for staff work (the admin console, Velvet, Backstage, Focus, working a door). Its
    /// roles grant what they grant there and it turns anyone else away. The member SDK speaks only to the consumer
    /// endpoint, so StaffKit adds this one.
    public static let staff = GraphQLEndpoint(rawValue: "staffql")

    /// `/v1/staffql`, with no audience: one staff sign-in, one human. It takes the platform sign-in (before any audience
    /// is chosen); `me { listings }` is everything the person manages anywhere, listed in no audience or any number,
    /// and `me { staffAudiences }` the audiences they work in, each worked inside at ``staff`` (its scope).
    public static let audiencelessStaff = GraphQLEndpoint(rawValue: "staffql", audienceless: true)
}
