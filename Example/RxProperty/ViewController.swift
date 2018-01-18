//
//  ViewController.swift
//  RxProperty
//
//  Created by gkaimakas on 12/29/2017.
//  Copyright (c) 2017 gkaimakas. All rights reserved.
//

import UIKit
import RxSwift
import RxProperty

class ViewController: UIViewController {

    var property: Property<Int?>!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        let observable = Observable<Int>.create ({
            $0.onNext(1)
            $0.onNext(2)
            $0.onNext(3)

            return Disposables.create()
        })

        let mProperty = MutableProperty<Int?>(nil)

        property = Property(mProperty)

        property
            .asObservable()
            .subscribe(onNext: {
                print($0)
            })

        mProperty.value = 1
        mProperty.value = 12
        mProperty.value = 1234
        mProperty.value = 12345
        mProperty.value = 134567
        mProperty.value = 13456768
        mProperty.value = nil

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

