import React, { useEffect, useRef } from 'react';
import { View, StyleSheet, Animated } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';

const SplashScreen = () => {
    const fadeAnim = useRef(new Animated.Value(0)).current;
    const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();

    useEffect(() => {
        Animated.timing(fadeAnim, {
            toValue: 1,
            duration: 1500,
            useNativeDriver: true,
        }).start(() => {
            setTimeout(() => {
                navigation.replace('Login');
            }, 1000); // Delay before moving to login
        });
    }, [fadeAnim, navigation]);

    return (
        <View style={styles.container}>
            <Animated.Text style={[styles.text, { opacity: fadeAnim }]}>
                E-Commerce App
            </Animated.Text>
        </View>
    );
};

export default SplashScreen;

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#0f172a',
        justifyContent: 'center',
        alignItems: 'center',
    },
    text: {
        color: 'white',
        fontSize: 32,
        fontWeight: 'bold',
    },
});
