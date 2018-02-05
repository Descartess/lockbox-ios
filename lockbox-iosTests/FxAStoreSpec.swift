/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Quick
import Nimble
import RxSwift
import RxTest

@testable import Lockbox

enum FxAStoreSharedExamples: String {
    case SaveScopedKeyToKeychain, SaveProfileInfoToKeychain
}

class FxAStoreSpec : QuickSpec {
    class FakeDispatcher : Dispatcher {
        let fakeRegistration = PublishSubject<Action>()

        override var register: Observable<Action> {
            return self.fakeRegistration.asObservable()
        }
    }

    class FakeKeychainManager : KeychainManager {
        var saveArguments:[KeychainManagerIdentifier:String] = [:]
        var saveSuccess:Bool!
        var retrieveArguments:[KeychainManagerIdentifier] = []
        var retrieveResult:[KeychainManagerIdentifier:String] = [:]

        override func save(_ data: String, identifier: KeychainManagerIdentifier) -> Bool {
            self.saveArguments[identifier] = data
            return saveSuccess
        }

        override func retrieve(_ identifier: KeychainManagerIdentifier) -> String? {
            self.retrieveArguments.append(identifier)
            return retrieveResult[identifier]
        }
    }

    private var dispatcher:FakeDispatcher!
    private var keychainManager:FakeKeychainManager!
    private var scheduler = TestScheduler(initialClock: 0)
    private var disposeBag = DisposeBag()
    var subject:FxAStore!

    override func spec() {
        describe("FxAStore") {
            beforeEach {
                self.dispatcher = FakeDispatcher()
                self.keychainManager = FakeKeychainManager()
                self.subject = FxAStore(dispatcher: self.dispatcher, keychainManager: self.keychainManager)
            }

            describe("fxADisplay") {
                var displayObserver = self.scheduler.createObserver(FxADisplayAction.self)
                beforeEach {
                    displayObserver = self.scheduler.createObserver(FxADisplayAction.self)

                    self.subject.fxADisplay
                            .drive(displayObserver)
                            .disposed(by: self.disposeBag)

                    self.dispatcher.fakeRegistration.onNext(FxADisplayAction.fetchingUserInformation)
                }

                it("pushes unique FxADisplay actions to observers") {
                    expect(displayObserver.events.count).to(be(1))
                    expect(displayObserver.events.first!.value.element).to(equal(FxADisplayAction.fetchingUserInformation))
                }

                it("only pushes unique FxADisplay actions to observers") {
                    self.dispatcher.fakeRegistration.onNext(FxADisplayAction.fetchingUserInformation)
                    expect(displayObserver.events.count).to(be(1))

                    self.dispatcher.fakeRegistration.onNext(FxADisplayAction.finishedFetchingUserInformation)
                    expect(displayObserver.events.count).to(be(2))
                }

                it("does not push non-FxADisplayAction actions") {
                    self.dispatcher.fakeRegistration.onNext(DataStoreAction.list(list: []))
                    expect(displayObserver.events.count).to(be(1))
                }
            }

            describe("scopedKey") {
                var keyObserver = self.scheduler.createObserver(String.self)
                let key = "fsdlkjsdfljafsdjlkfdsajkldf"

                beforeEach {
                    keyObserver = self.scheduler.createObserver(String.self)

                    self.subject.scopedKey
                            .bind(to: keyObserver)
                            .disposed(by: self.disposeBag)
                }

                sharedExamples(FxAStoreSharedExamples.SaveScopedKeyToKeychain.rawValue) {
                    it("attempts to save the scoped key to the keychain") {
                        expect(self.keychainManager.saveArguments[.scopedKey]).notTo(beNil())
                        expect(self.keychainManager.saveArguments[.scopedKey]).to(equal(key))
                    }
                }

                describe("when the key is saved to the key manager successfully") {
                    beforeEach {
                        self.keychainManager.saveSuccess = true
                        self.dispatcher.fakeRegistration.onNext(FxAInformationAction.scopedKey(key: key))
                    }

                    itBehavesLike(FxAStoreSharedExamples.SaveScopedKeyToKeychain.rawValue)

                    it("pushes the scopedKey to the observers") {
                        expect(keyObserver.events.first!.value.element).to(equal(key))
                    }
                }

                describe("when the key is not saved to the key manager successfully") {
                    beforeEach {
                        self.keychainManager.saveSuccess = false
                        self.dispatcher.fakeRegistration.onNext(FxAInformationAction.scopedKey(key: key))
                    }

                    itBehavesLike(FxAStoreSharedExamples.SaveScopedKeyToKeychain.rawValue)

                    it("does not push the scopedKey to the observers") {
                        expect(keyObserver.events.count).to(be(0))
                    }
                }
            }

            describe("ProfileInfo") {
                var profileInfoObserver = self.scheduler.createObserver(ProfileInfo.self)
                let profileInfo = ProfileInfo.Builder()
                        .uid("jklfsdlkjdfs")
                        .email("sand@sand.com")
                        .build()

                beforeEach {
                    profileInfoObserver = self.scheduler.createObserver(ProfileInfo.self)

                    self.subject.profileInfo
                            .bind(to: profileInfoObserver)
                            .disposed(by: self.disposeBag)
                }

                sharedExamples(FxAStoreSharedExamples.SaveProfileInfoToKeychain.rawValue) {
                    it("attempts to save the uid and email to the keychain") {
                        expect(self.keychainManager.saveArguments[.email]).to(equal(profileInfo.email))
                        expect(self.keychainManager.saveArguments[.uid]).to(equal(profileInfo.uid))
                    }
                }

                describe("when the email & uid are saved successfully to the keychain") {
                    beforeEach {
                        self.keychainManager.saveSuccess = true
                        self.dispatcher.fakeRegistration.onNext(FxAInformationAction.profileInfo(info: profileInfo))
                    }

                    itBehavesLike(FxAStoreSharedExamples.SaveProfileInfoToKeychain.rawValue)

                    it("pushes the profileInfo to the observer") {
                        expect(profileInfoObserver.events.first!.value.element).to(equal(profileInfo))
                    }
                }

                describe("when only the email or uid is saved successfully to the keychain") {
                    beforeEach {
                        self.keychainManager.saveSuccess = false
                        self.dispatcher.fakeRegistration.onNext(FxAInformationAction.profileInfo(info: profileInfo))
                    }

                    it("pushes nothing to the observer") {
                        expect(profileInfoObserver.events.count).to(be(0))
                    }
                }
            }

            describe("OAuthInfo") {
                var oAuthInfoObserver = self.scheduler.createObserver(OAuthInfo.self)
                let oauthInfo = OAuthInfo.Builder()
                        .idToken("fdskjldsflkjdfs")
                        .accessToken("mekhjfdsj")
                        .refreshToken("fdssfdjhk")
                        .build()

                beforeEach {
                    oAuthInfoObserver = self.scheduler.createObserver(OAuthInfo.self)

                    self.subject.oauthInfo
                            .bind(to: oAuthInfoObserver)
                            .disposed(by: self.disposeBag)
                }

                describe("when the tokens are saved successfully to the keychain") {
                    beforeEach {
                        self.keychainManager.saveSuccess = true
                        self.dispatcher.fakeRegistration.onNext(FxAInformationAction.oauthInfo(info: oauthInfo))
                    }

                    it("attempts to save the tokens to the keychain") {
                        expect(self.keychainManager.saveArguments[.idToken]).to(equal(oauthInfo.idToken))
                        expect(self.keychainManager.saveArguments[.accessToken]).to(equal(oauthInfo.accessToken))
                        expect(self.keychainManager.saveArguments[.refreshToken]).to(equal(oauthInfo.refreshToken))
                    }

                    it("pushes the profileInfo to the observer") {
                        expect(oAuthInfoObserver.events.first!.value.element).to(equal(oauthInfo))
                    }
                }

                describe("when nothing is saved successfully to the keychain") {
                    beforeEach {
                        self.keychainManager.saveSuccess = false
                        self.dispatcher.fakeRegistration.onNext(FxAInformationAction.oauthInfo(info: oauthInfo))
                    }

                    it("attempts to save tokens to the keychain") {
                        expect(self.keychainManager.saveArguments[.accessToken]).to(equal(oauthInfo.accessToken))
                    }

                    it("pushes nothing to the observer") {
                        expect(oAuthInfoObserver.events.count).to(be(0))
                    }
                }
            }

            describe("populating initial values") {
                describe("ProfileInfo") {
                    var profileInfoObserver = self.scheduler.createObserver(ProfileInfo.self)

                    beforeEach {
                        profileInfoObserver = self.scheduler.createObserver(ProfileInfo.self)
                    }

                    describe("when both uid and email have previously been saved in the keychain") {
                        let email = "butts@butts.com"
                        let uid = "kjfdslkjsdflkjads"
                        beforeEach {
                            self.keychainManager.retrieveResult[.email] = email
                            self.keychainManager.retrieveResult[.uid] = uid

                            self.subject = FxAStore(dispatcher: self.dispatcher, keychainManager: self.keychainManager)

                            self.subject.profileInfo
                                    .bind(to: profileInfoObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("passes the resulting profileinfo object to subscribers") {
                            expect(profileInfoObserver.events.first!.value.element).to(equal(ProfileInfo.Builder().uid(uid).email(email).build()))
                        }
                    }

                    describe("when only uid has been saved in the keychain") {
                        let uid = "kjfdslkjsdflkjads"
                        beforeEach {
                            self.keychainManager.retrieveResult[.uid] = uid

                            self.subject = FxAStore(dispatcher: self.dispatcher, keychainManager: self.keychainManager)

                            self.subject.profileInfo
                                    .bind(to: profileInfoObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("passes nothing to subscribers") {
                            expect(profileInfoObserver.events.count).to(be(0))
                        }
                    }

                    describe("when only email has been saved in the keychain") {
                        let email = "butts@butts.com"
                        beforeEach {
                            self.keychainManager.retrieveResult[.email] = email

                            self.subject = FxAStore(dispatcher: self.dispatcher, keychainManager: self.keychainManager)

                            self.subject.profileInfo
                                    .bind(to: profileInfoObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("passes nothing to subscribers") {
                            expect(profileInfoObserver.events.count).to(be(0))
                        }
                    }

                    describe("when neither have been saved in the keychain") {
                        beforeEach {
                            self.subject.profileInfo
                                    .bind(to: profileInfoObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("passes nothing to subscribers") {
                            expect(profileInfoObserver.events.count).to(be(0))
                        }
                    }
                }

                describe("scopedKey") {
                    var keyObserver = self.scheduler.createObserver(String.self)
                    let key = "fsdlkjsdfljafsdjlkfdsajkldf"

                    beforeEach {
                        keyObserver = self.scheduler.createObserver(String.self)
                    }

                    describe("when the scopedKey has previously been saved to the keychain") {
                        beforeEach {
                            self.keychainManager.retrieveResult[.scopedKey] = key
                            self.subject = FxAStore(dispatcher: self.dispatcher, keychainManager: self.keychainManager)

                            self.subject.scopedKey
                                    .bind(to: keyObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("stores the key for subsequent observers") {
                            expect(keyObserver.events.first!.value.element).to(equal(key))
                        }
                    }
                    describe("when the scopedKey has not previously been saved to the keychain") {
                        beforeEach {
                            self.subject.scopedKey
                                    .bind(to: keyObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("pushes nothing to key observers") {
                            expect(keyObserver.events.count).to(be(0))
                        }
                    }
                }

                describe("OAuthInfo") {
                    var oAuthInfoObserver = self.scheduler.createObserver(OAuthInfo.self)

                    beforeEach {
                        oAuthInfoObserver = self.scheduler.createObserver(OAuthInfo.self)
                    }

                    describe("when all tokens have previously been saved in the keychain") {
                        let accessToken = "meow"
                        let idToken = "kjfdslkjsdflkjads"
                        let refreshToken = "fsdkjlkfsdfddf"

                        beforeEach {
                            self.keychainManager.retrieveResult[.accessToken] = accessToken
                            self.keychainManager.retrieveResult[.idToken] = idToken
                            self.keychainManager.retrieveResult[.refreshToken] = refreshToken

                            self.subject = FxAStore(dispatcher: self.dispatcher, keychainManager: self.keychainManager)

                            self.subject.oauthInfo
                                    .bind(to: oAuthInfoObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("passes the resulting oauthInfo object to subscribers") {
                            expect(oAuthInfoObserver.events.first!.value.element).to(equal(OAuthInfo.Builder()
                                    .idToken(idToken)
                                    .refreshToken(refreshToken)
                                    .accessToken(accessToken)
                                    .build()
                            ))
                        }
                    }

                    describe("when not all tokens have been saved in the keychain") {
                        let accessToken = "meow"
                        let refreshToken = "fsdkjlkfsdfddf"

                        beforeEach {
                            self.keychainManager.retrieveResult[.accessToken] = accessToken
                            self.keychainManager.retrieveResult[.refreshToken] = refreshToken

                            self.subject = FxAStore(dispatcher: self.dispatcher, keychainManager: self.keychainManager)

                            self.subject.oauthInfo
                                    .bind(to: oAuthInfoObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("passes nothing to subscribers") {
                            expect(oAuthInfoObserver.events.count).to(be(0))
                        }
                    }

                    describe("when no tokens have been saved in the keychain") {
                        beforeEach {
                            self.subject.oauthInfo
                                    .bind(to: oAuthInfoObserver)
                                    .disposed(by: self.disposeBag)
                        }

                        it("passes nothing to subscribers") {
                            expect(oAuthInfoObserver.events.count).to(be(0))
                        }
                    }
                }
            }
        }
    }
}
